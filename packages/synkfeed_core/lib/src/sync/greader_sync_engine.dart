import '../models/article.dart';
import '../models/article_state.dart';
import '../models/feed.dart';
import '../models/subscription.dart';
import '../repository/local_feed_repository.dart';
import 'auth_session.dart';
import 'greader_api_client.dart';
import 'sync_engine.dart';

/// Prefix shared by feeds, subscriptions, and articles that originate from a
/// Google Reader-compatible server, so pending operations can be mapped back
/// to server item IDs.
const String greaderEntityPrefix = 'greader-';

/// Synchronizes with a Google Reader-compatible server such as FreshRSS.
///
/// Unlike the native [SyncEngine], the server is the source of subscriptions
/// and articles: feeds and article content (full text when FreshRSS is
/// configured to retrieve it) are downloaded, local read/star changes are
/// replayed through `edit-tag`, and read/star state is reconciled from the
/// server's unread and starred ID sets.
class GReaderSyncEngine {
  GReaderSyncEngine({
    required this.repository,
    required this.client,
    required this.sessionStore,
    this.localUserId = 'local-user',
    this.pageSize = 100,
    this.maxArticles = 500,
  });

  final LocalFeedRepository repository;
  final GReaderApiClient client;
  final SessionStore sessionStore;
  final String localUserId;
  final int pageSize;
  final int maxArticles;

  Future<SyncReport> synchronize() async {
    final session = await sessionStore.load();
    if (session == null || session.backend != SyncBackend.greader) {
      throw const SyncAuthException(
        'No active FreshRSS session. Sign in first.',
      );
    }
    final auth = session.accessToken;
    try {
      final pushReport = await _pushPendingOperations(auth);
      final applied = await _pullServerState(auth);
      return SyncReport(
        pushedOperations: pushReport.$1,
        rejectedOperations: pushReport.$2,
        appliedChanges: applied,
        cursor: 0,
      );
    } on GReaderApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await sessionStore.clear();
        throw const SyncAuthException(
          'FreshRSS rejected the credentials. Sign in again.',
        );
      }
      rethrow;
    }
  }

  Future<(int, int)> _pushPendingOperations(String auth) async {
    final operations = await repository.listPendingOperations();
    if (operations.isEmpty) {
      return (0, 0);
    }
    var pushed = 0;
    var rejected = 0;
    final writeToken = await client.writeToken(authToken: auth);
    for (final operation in operations) {
      if (operation.entityType != 'article_state' ||
          !operation.entityId.startsWith(greaderEntityPrefix)) {
        // Only server-known articles can be replayed to FreshRSS.
        await repository.markOperationRejected(
          operation.operationId,
          'not_linked',
        );
        rejected += 1;
        continue;
      }
      final itemId = operation.entityId.substring(greaderEntityPrefix.length);
      final isRead = operation.operationType == 'mark_read';
      final tag = isRead ? GReaderStreams.read : GReaderStreams.starred;
      final value = operation.payload[isRead ? 'isRead' : 'isStarred'] == true;
      await client.editTag(
        authToken: auth,
        writeToken: writeToken,
        itemIds: <String>[itemId],
        addTag: value ? tag : null,
        removeTag: value ? null : tag,
      );
      await repository.acknowledgeOperation(operation.operationId);
      pushed += 1;
    }
    return (pushed, rejected);
  }

  Future<int> _pullServerState(String auth) async {
    final now = DateTime.now().toUtc();
    var applied = 0;

    final subscriptions = await client.listSubscriptions(authToken: auth);
    final existingSubscriptions = <String, Subscription>{
      for (final subscription in await repository.listSubscriptions(
        userId: localUserId,
      ))
        subscription.feedId: subscription,
    };
    final feedIds = <String>{};
    for (final subscription in subscriptions) {
      final feedId = '$greaderEntityPrefix${subscription.id}';
      feedIds.add(feedId);
      final fallbackUrl = Uri.parse('greader:${subscription.id}');
      await repository.upsertFeed(
        Feed(
          id: feedId,
          canonicalUrl: subscription.htmlUrl ?? subscription.url ?? fallbackUrl,
          feedUrl: subscription.url ?? fallbackUrl,
          siteUrl: subscription.htmlUrl,
          title: subscription.title,
          iconUrl: subscription.iconUrl,
          lastFetchedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (!existingSubscriptions.containsKey(feedId)) {
        await repository.upsertSubscription(
          Subscription(
            id: 'subscription-$feedId',
            userId: localUserId,
            feedId: feedId,
            createdAt: now,
            updatedAt: now,
          ),
        );
        applied += 1;
      }
    }

    final articles = <Article>[];
    String? continuation;
    while (articles.length < maxArticles) {
      final page = await client.streamContents(
        authToken: auth,
        count: pageSize,
        continuation: continuation,
      );
      for (final item in page.items) {
        final feedId = '$greaderEntityPrefix${item.streamId}';
        if (!feedIds.contains(feedId)) {
          continue;
        }
        final contentHtml = item.contentHtml;
        articles.add(
          Article(
            id: '$greaderEntityPrefix${item.id}',
            feedId: feedId,
            externalId: item.id,
            canonicalUrl: item.url ?? Uri.parse('greader:item/${item.id}'),
            title: item.title,
            author: item.author,
            contentHtml: contentHtml,
            contentText: contentHtml == null ? null : _stripHtml(contentHtml),
            publishedAt: item.publishedAt,
            downloadedAt: now,
            insertedAt: now,
          ),
        );
      }
      continuation = page.continuation;
      if (continuation == null || page.items.isEmpty) {
        break;
      }
    }
    await repository.upsertArticles(articles);
    applied += articles.length;

    final unreadIds = await client.streamItemIds(
      authToken: auth,
      streamId: GReaderStreams.readingList,
      excludeTarget: GReaderStreams.read,
    );
    final starredIds = await client.streamItemIds(
      authToken: auth,
      streamId: GReaderStreams.starred,
    );
    for (final article in await repository.listArticles(userId: localUserId)) {
      if (!article.id.startsWith(greaderEntityPrefix)) {
        continue;
      }
      final shouldBeRead = !unreadIds.contains(article.externalId);
      final shouldBeStarred = starredIds.contains(article.externalId);
      final current = await repository.getArticleState(
        userId: localUserId,
        articleId: article.id,
      );
      if (current == null && !shouldBeRead && !shouldBeStarred) {
        continue;
      }
      if (current != null &&
          current.isRead == shouldBeRead &&
          current.isStarred == shouldBeStarred) {
        continue;
      }
      final base =
          current ??
          ArticleState(
            userId: localUserId,
            articleId: article.id,
            isRead: false,
            isStarred: false,
            isArchived: false,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            logicalVersion: 0,
          );
      // Applied through the state upsert, not the operation-producing
      // helpers, so reconciliation never re-queues server state as pending.
      await repository.upsertArticleState(
        base.copyWith(
          isRead: shouldBeRead,
          readAt: shouldBeRead ? (base.readAt ?? now) : null,
          isStarred: shouldBeStarred,
          starredAt: shouldBeStarred ? (base.starredAt ?? now) : null,
          updatedAt: now,
          logicalVersion: base.logicalVersion + 1,
        ),
      );
      applied += 1;
    }
    return applied;
  }
}

String _stripHtml(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
