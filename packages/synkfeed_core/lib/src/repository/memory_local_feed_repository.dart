import '../models/article.dart';
import '../models/article_state.dart';
import '../models/feed.dart';
import '../models/remote_change.dart';
import '../models/retention_policy.dart';
import '../models/sync_operation.dart';
import '../models/subscription.dart';
import 'local_feed_repository.dart';

class MemoryLocalFeedRepository implements LocalFeedRepository {
  final Map<String, Feed> _feeds = <String, Feed>{};
  final Map<String, Article> _articles = <String, Article>{};
  final Map<String, ArticleState> _articleStates = <String, ArticleState>{};
  final Map<String, Subscription> _subscriptions = <String, Subscription>{};
  final Map<String, RetentionPolicy> _retentionPolicies =
      <String, RetentionPolicy>{};
  final List<SyncOperation> _pendingOperations = <SyncOperation>[];
  final List<SyncOperation> _rejectedOperations = <SyncOperation>[];
  final Map<String, int> _clientSequences = <String, int>{};
  final Map<String, int> _syncCursors = <String, int>{};

  @override
  Future<void> upsertFeed(Feed feed) async {
    _feeds[feed.id] = feed;
  }

  @override
  Future<void> upsertArticles(Iterable<Article> articles) async {
    for (final article in articles) {
      _articles[article.id] = article;
    }
  }

  @override
  Future<List<Feed>> listFeeds() async {
    final items = _feeds.values.toList(growable: false)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return items;
  }

  @override
  Future<void> upsertSubscription(Subscription subscription) async {
    _subscriptions[subscription.id] = subscription;
  }

  @override
  Future<List<Subscription>> listSubscriptions({required String userId}) async {
    final items =
        _subscriptions.values
            .where(
              (subscription) =>
                  subscription.userId == userId &&
                  subscription.deletedAt == null,
            )
            .toList(growable: false)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  @override
  Future<void> deleteSubscription({
    required String subscriptionId,
    required DateTime deletedAt,
  }) async {
    final current = _subscriptions[subscriptionId];
    if (current != null) {
      _subscriptions[subscriptionId] = current.copyWith(
        deletedAt: deletedAt,
        updatedAt: deletedAt,
        syncVersion: current.syncVersion + 1,
      );
    }
  }

  @override
  Future<RetentionPolicy> getRetentionPolicy(String userId) async {
    return _retentionPolicies[userId] ?? const RetentionPolicy();
  }

  @override
  Future<void> saveRetentionPolicy(
    String userId,
    RetentionPolicy policy,
  ) async {
    _retentionPolicies[userId] = policy;
  }

  @override
  Future<int> cleanUpArticles({
    required String userId,
    required DateTime now,
  }) async {
    final policy = await getRetentionPolicy(userId);
    final candidates = <String>{};
    if (policy.retentionDays != null) {
      final cutoff = now.toUtc().subtract(
        Duration(days: policy.retentionDays!),
      );
      for (final article in _articles.values) {
        if ((article.publishedAt ?? article.insertedAt).isBefore(cutoff) &&
            _canRemove(article.id, userId, policy)) {
          candidates.add(article.id);
        }
      }
    }
    final maximum = policy.maximumArticlesPerFeed;
    if (maximum != null) {
      for (final feed in _feeds.values) {
        final articles =
            _articles.values
                .where((article) => article.feedId == feed.id)
                .toList()
              ..sort(
                (a, b) => (b.publishedAt ?? b.insertedAt).compareTo(
                  a.publishedAt ?? a.insertedAt,
                ),
              );
        for (final article in articles.skip(maximum)) {
          if (_canRemove(article.id, userId, policy)) {
            candidates.add(article.id);
          }
        }
      }
    }
    for (final articleId in candidates) {
      _articles.remove(articleId);
      _articleStates.removeWhere((key, value) => value.articleId == articleId);
    }
    return candidates.length;
  }

  bool _canRemove(String articleId, String userId, RetentionPolicy policy) {
    final state = _articleStates[_stateKey(userId, articleId)];
    if (policy.preserveUnread && state?.isRead != true) {
      return false;
    }
    if (policy.preserveStarred && state?.isStarred == true) {
      return false;
    }
    return true;
  }

  @override
  Future<List<Article>> listArticles({
    required String userId,
    String? feedId,
    bool unreadOnly = false,
    bool starredOnly = false,
    String? searchQuery,
  }) async {
    final filtered = _articles.values
        .where((article) {
          if (feedId != null && article.feedId != feedId) {
            return false;
          }

          final state = _articleStates[_stateKey(userId, article.id)];
          if (unreadOnly && state?.isRead == true) {
            return false;
          }
          if (starredOnly && state?.isStarred != true) {
            return false;
          }
          final normalizedQuery = searchQuery?.trim().toLowerCase();
          if (normalizedQuery != null &&
              normalizedQuery.isNotEmpty &&
              !article.title.toLowerCase().contains(normalizedQuery)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      final aPublished =
          a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bPublished =
          b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final comparison = bPublished.compareTo(aPublished);
      if (comparison != 0) {
        return comparison;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filtered;
  }

  @override
  Future<ArticleState?> getArticleState({
    required String userId,
    required String articleId,
  }) async {
    return _articleStates[_stateKey(userId, articleId)];
  }

  @override
  Future<ArticleState> upsertArticleState(ArticleState state) async {
    _articleStates[_stateKey(state.userId, state.articleId)] = state;
    return state;
  }

  @override
  Future<int> nextClientSequence(String deviceId) async {
    final next = (_clientSequences[deviceId] ?? 0) + 1;
    _clientSequences[deviceId] = next;
    return next;
  }

  @override
  Future<SyncOperation?> markArticleRead({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required bool isRead,
    DateTime? occurredAt,
  }) async {
    return _writeState(
      userId: userId,
      deviceId: deviceId,
      clientSequence: clientSequence,
      articleId: articleId,
      operationType: 'mark_read',
      value: isRead,
      occurredAt: occurredAt,
      read: true,
    );
  }

  @override
  Future<SyncOperation?> toggleArticleStar({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required bool isStarred,
    DateTime? occurredAt,
  }) async {
    return _writeState(
      userId: userId,
      deviceId: deviceId,
      clientSequence: clientSequence,
      articleId: articleId,
      operationType: 'toggle_star',
      value: isStarred,
      occurredAt: occurredAt,
      read: false,
    );
  }

  @override
  Future<List<SyncOperation>> listPendingOperations() async {
    return List<SyncOperation>.unmodifiable(_pendingOperations);
  }

  @override
  Future<void> acknowledgeOperation(String operationId) async {
    _pendingOperations.removeWhere(
      (operation) => operation.operationId == operationId,
    );
  }

  @override
  Future<void> markOperationRejected(
    String operationId,
    String errorCode,
  ) async {
    final index = _pendingOperations.indexWhere(
      (operation) => operation.operationId == operationId,
    );
    if (index == -1) {
      return;
    }
    _rejectedOperations.add(
      _pendingOperations
          .removeAt(index)
          .copyWith(status: 'rejected', errorCode: errorCode),
    );
  }

  @override
  Future<List<SyncOperation>> reassignPendingOperations({
    required String deviceId,
  }) async {
    for (var index = 0; index < _pendingOperations.length; index += 1) {
      final operation = _pendingOperations[index];
      if (operation.deviceId == deviceId) {
        continue;
      }
      final sequence = await nextClientSequence(deviceId);
      _pendingOperations[index] = operation.copyWith(
        operationId:
            '$deviceId:${operation.entityId}:$sequence:${operation.operationType}',
        deviceId: deviceId,
        clientSequence: sequence,
      );
    }
    return listPendingOperations();
  }

  @override
  Future<int> getSyncCursor(String userId) async => _syncCursors[userId] ?? 0;

  @override
  Future<void> applyRemoteChanges({
    required String userId,
    required List<RemoteChange> changes,
    required int nextCursor,
  }) async {
    for (final change in changes) {
      final state = change.toArticleState(userId);
      if (state == null || !_articles.containsKey(state.articleId)) {
        continue;
      }
      _articleStates[_stateKey(userId, state.articleId)] = state;
    }
    _syncCursors[userId] = nextCursor;
  }

  @override
  Future<void> close() async {}

  Future<SyncOperation?> _writeState({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required String operationType,
    required bool value,
    required DateTime? occurredAt,
    required bool read,
  }) async {
    final key = _stateKey(userId, articleId);
    final current =
        _articleStates[key] ??
        ArticleState(
          userId: userId,
          articleId: articleId,
          isRead: false,
          readAt: null,
          isStarred: false,
          starredAt: null,
          isArchived: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          logicalVersion: 0,
        );

    final effectiveAt = occurredAt ?? DateTime.now().toUtc();
    final unchanged = read
        ? current.isRead == value
        : current.isStarred == value;
    if (unchanged) {
      return null;
    }

    final updated = read
        ? current.copyWith(
            isRead: value,
            readAt: value ? effectiveAt : null,
            updatedAt: effectiveAt,
            logicalVersion: current.logicalVersion + 1,
          )
        : current.copyWith(
            isStarred: value,
            starredAt: value ? effectiveAt : null,
            updatedAt: effectiveAt,
            logicalVersion: current.logicalVersion + 1,
          );

    _articleStates[key] = updated;
    final operation = SyncOperation(
      operationId: '$deviceId:$articleId:$clientSequence:$operationType',
      deviceId: deviceId,
      entityType: 'article_state',
      entityId: articleId,
      operationType: operationType,
      payload: read
          ? <String, Object?>{'isRead': value}
          : <String, Object?>{'isStarred': value},
      clientSequence: clientSequence,
      createdAt: effectiveAt,
    );
    _pendingOperations.add(operation);
    return operation;
  }

  String _stateKey(String userId, String articleId) => '$userId::$articleId';
}
