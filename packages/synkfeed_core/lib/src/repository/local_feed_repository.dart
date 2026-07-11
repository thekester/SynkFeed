import '../models/article.dart';
import '../models/article_state.dart';
import '../models/feed.dart';
import '../models/sync_operation.dart';

abstract class LocalFeedRepository {
  Future<void> upsertFeed(Feed feed);

  Future<void> upsertArticles(Iterable<Article> articles);

  Future<List<Feed>> listFeeds();

  Future<List<Article>> listArticles({
    required String userId,
    String? feedId,
    bool unreadOnly = false,
    bool starredOnly = false,
  });

  Future<ArticleState?> getArticleState({
    required String userId,
    required String articleId,
  });

  Future<ArticleState> upsertArticleState(ArticleState state);

  Future<SyncOperation?> markArticleRead({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required bool isRead,
    DateTime? occurredAt,
  });

  Future<SyncOperation?> toggleArticleStar({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required bool isStarred,
    DateTime? occurredAt,
  });

  Future<List<SyncOperation>> listPendingOperations();

  Future<void> acknowledgeOperation(String operationId);
}
