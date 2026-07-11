import '../models/article.dart';
import '../models/article_state.dart';
import '../models/feed.dart';
import '../models/sync_operation.dart';
import 'local_feed_repository.dart';

class MemoryLocalFeedRepository implements LocalFeedRepository {
  final Map<String, Feed> _feeds = <String, Feed>{};
  final Map<String, Article> _articles = <String, Article>{};
  final Map<String, ArticleState> _articleStates = <String, ArticleState>{};
  final List<SyncOperation> _pendingOperations = <SyncOperation>[];

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
  Future<List<Article>> listArticles({
    required String userId,
    String? feedId,
    bool unreadOnly = false,
    bool starredOnly = false,
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
