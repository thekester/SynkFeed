import 'dart:io';

import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  test('persists articles, states, operations, and sequences', () async {
    final directory = await Directory.systemTemp.createTemp('synkfeed-test-');
    final path = '${directory.path}${Platform.pathSeparator}reader.sqlite';
    addTearDown(() => directory.delete(recursive: true));

    final now = DateTime.utc(2026, 7, 11, 12);
    final feed = Feed(
      id: 'feed-1',
      canonicalUrl: Uri.parse('https://example.com'),
      feedUrl: Uri.parse('https://example.com/feed.xml'),
      title: 'Example',
      createdAt: now,
      updatedAt: now,
    );
    final article = Article(
      id: 'article-1',
      feedId: feed.id,
      externalId: 'guid-1',
      canonicalUrl: Uri.parse('https://example.com/articles/1'),
      title: 'First article',
      publishedAt: now,
      insertedAt: now,
    );

    var repository = SqliteLocalFeedRepository(path);
    await repository.upsertFeed(feed);
    await repository.upsertArticles(<Article>[article]);
    await repository.upsertSubscription(
      Subscription(
        id: 'subscription-1',
        userId: 'user-1',
        feedId: feed.id,
        customTitle: 'My example',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final sequence = await repository.nextClientSequence('device-1');
    await repository.markArticleRead(
      userId: 'user-1',
      deviceId: 'device-1',
      clientSequence: sequence,
      articleId: article.id,
      isRead: true,
      occurredAt: now,
    );
    await repository.close();

    repository = SqliteLocalFeedRepository(path);
    addTearDown(repository.close);

    expect(await repository.listFeeds(), hasLength(1));
    expect(
      (await repository.listSubscriptions(userId: 'user-1')).single.customTitle,
      'My example',
    );
    expect(await repository.listArticles(userId: 'user-1'), hasLength(1));
    expect(
      await repository.listArticles(userId: 'user-1', searchQuery: 'FIRST'),
      hasLength(1),
    );
    expect(
      await repository.listArticles(userId: 'user-1', searchQuery: 'missing'),
      isEmpty,
    );
    expect(
      await repository.listArticles(userId: 'user-1', unreadOnly: true),
      isEmpty,
    );
    expect(
      (await repository.getArticleState(
        userId: 'user-1',
        articleId: article.id,
      ))?.isRead,
      isTrue,
    );
    expect(await repository.listPendingOperations(), hasLength(1));
    expect(await repository.nextClientSequence('device-1'), 2);

    await repository.deleteSubscription(
      subscriptionId: 'subscription-1',
      deletedAt: now.add(const Duration(minutes: 1)),
    );
    expect(await repository.listSubscriptions(userId: 'user-1'), isEmpty);
  });

  test(
    'retention removes old read articles but preserves protected ones',
    () async {
      final repository = SqliteLocalFeedRepository.inMemory();
      addTearDown(repository.close);
      final now = DateTime.utc(2026, 7, 11, 12);
      await repository.upsertFeed(
        Feed(
          id: 'feed-1',
          canonicalUrl: Uri.parse('https://example.com'),
          feedUrl: Uri.parse('https://example.com/feed.xml'),
          title: 'Example',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final articles = <Article>[
        _article('new-read', now.subtract(const Duration(days: 1))),
        _article('old-read', now.subtract(const Duration(days: 45))),
        _article('old-unread', now.subtract(const Duration(days: 46))),
        _article('old-starred', now.subtract(const Duration(days: 47))),
      ];
      await repository.upsertArticles(articles);
      await repository.upsertArticleState(
        _state('new-read', now, isRead: true),
      );
      await repository.upsertArticleState(
        _state('old-read', now, isRead: true),
      );
      await repository.upsertArticleState(
        _state('old-starred', now, isRead: true, isStarred: true),
      );
      await repository.saveRetentionPolicy(
        'user-1',
        const RetentionPolicy(retentionDays: 30, maximumArticlesPerFeed: 1),
      );

      expect(await repository.cleanUpArticles(userId: 'user-1', now: now), 1);
      final remaining = await repository.listArticles(userId: 'user-1');
      expect(
        remaining.map((article) => article.id),
        containsAll(<String>['new-read', 'old-unread', 'old-starred']),
      );
      expect(
        remaining.map((article) => article.id),
        isNot(contains('old-read')),
      );
    },
  );

  test(
    'reassigns pending operations, tracks rejections, and persists the cursor',
    () async {
      final directory = await Directory.systemTemp.createTemp('synkfeed-test-');
      final path = '${directory.path}${Platform.pathSeparator}sync.sqlite';
      addTearDown(() => directory.delete(recursive: true));

      final now = DateTime.utc(2026, 7, 11, 12);
      var repository = SqliteLocalFeedRepository(path);
      final feed = Feed(
        id: 'feed-1',
        canonicalUrl: Uri.parse('https://example.com'),
        feedUrl: Uri.parse('https://example.com/feed.xml'),
        title: 'Example',
        createdAt: now,
        updatedAt: now,
      );
      await repository.upsertFeed(feed);
      await repository.upsertArticles(<Article>[
        _article('article-1', now),
        _article('article-2', now),
      ]);
      await repository.markArticleRead(
        userId: 'local-user',
        deviceId: 'local-device',
        clientSequence: await repository.nextClientSequence('local-device'),
        articleId: 'article-1',
        isRead: true,
        occurredAt: now,
      );
      await repository.toggleArticleStar(
        userId: 'local-user',
        deviceId: 'local-device',
        clientSequence: await repository.nextClientSequence('local-device'),
        articleId: 'article-2',
        isStarred: true,
        occurredAt: now,
      );

      final rebound = await repository.reassignPendingOperations(
        deviceId: 'device-uuid',
      );
      expect(rebound.map((op) => op.deviceId).toSet(), {'device-uuid'});
      expect(rebound.map((op) => op.clientSequence).toList(), [1, 2]);
      expect(
        rebound.first.operationId,
        'device-uuid:article-1:1:mark_read',
      );
      // A second pass leaves already-bound operations untouched.
      final unchanged = await repository.reassignPendingOperations(
        deviceId: 'device-uuid',
      );
      expect(
        unchanged.map((op) => op.operationId).toList(),
        rebound.map((op) => op.operationId).toList(),
      );

      await repository.markOperationRejected(
        rebound.last.operationId,
        'article_not_found',
      );
      expect(await repository.listPendingOperations(), hasLength(1));

      expect(await repository.getSyncCursor('local-user'), 0);
      await repository.applyRemoteChanges(
        userId: 'local-user',
        changes: <RemoteChange>[
          const RemoteChange(
            cursor: 4,
            entityType: 'article_state',
            entityId: 'article-2',
            operationType: 'toggle_star',
            data: {
              'is_read': false,
              'read_at': null,
              'is_starred': true,
              'starred_at': '2026-07-11T12:30:00.000Z',
              'is_archived': false,
              'logical_version': '7',
            },
          ),
          const RemoteChange(
            cursor: 5,
            entityType: 'article_state',
            entityId: 'unknown-article',
            operationType: 'mark_read',
            data: {'is_read': true},
          ),
        ],
        nextCursor: 5,
      );
      await repository.close();

      repository = SqliteLocalFeedRepository(path);
      addTearDown(repository.close);
      expect(await repository.getSyncCursor('local-user'), 5);
      final state = await repository.getArticleState(
        userId: 'local-user',
        articleId: 'article-2',
      );
      expect(state?.isStarred, isTrue);
      expect(state?.logicalVersion, 7);
      expect(
        await repository.getArticleState(
          userId: 'local-user',
          articleId: 'unknown-article',
        ),
        isNull,
      );
    },
  );
}

Article _article(String id, DateTime publishedAt) => Article(
  id: id,
  feedId: 'feed-1',
  externalId: id,
  canonicalUrl: Uri.parse('https://example.com/$id'),
  title: id,
  publishedAt: publishedAt,
  insertedAt: publishedAt,
);

ArticleState _state(
  String articleId,
  DateTime now, {
  required bool isRead,
  bool isStarred = false,
}) => ArticleState(
  userId: 'user-1',
  articleId: articleId,
  isRead: isRead,
  readAt: isRead ? now : null,
  isStarred: isStarred,
  starredAt: isStarred ? now : null,
  isArchived: false,
  updatedAt: now,
  logicalVersion: 1,
);
