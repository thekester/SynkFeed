import '../models/article.dart';
import '../models/article_state.dart';
import '../models/feed.dart';
import '../models/remote_change.dart';
import '../models/retention_policy.dart';
import '../models/sync_operation.dart';
import '../models/subscription.dart';

abstract class LocalFeedRepository {
  Future<void> upsertFeed(Feed feed);

  Future<void> upsertArticles(Iterable<Article> articles);

  Future<List<Feed>> listFeeds();

  Future<void> upsertSubscription(Subscription subscription);

  Future<List<Subscription>> listSubscriptions({required String userId});

  Future<void> deleteSubscription({
    required String subscriptionId,
    required DateTime deletedAt,
  });

  Future<RetentionPolicy> getRetentionPolicy(String userId);

  Future<void> saveRetentionPolicy(String userId, RetentionPolicy policy);

  Future<int> cleanUpArticles({required String userId, required DateTime now});

  Future<List<Article>> listArticles({
    required String userId,
    String? feedId,
    bool unreadOnly = false,
    bool starredOnly = false,
    String? searchQuery,
  });

  Future<ArticleState?> getArticleState({
    required String userId,
    required String articleId,
  });

  Future<ArticleState> upsertArticleState(ArticleState state);

  Future<int> nextClientSequence(String deviceId);

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

  Future<void> markOperationRejected(String operationId, String errorCode);

  /// Rebinds pending operations recorded under another device identity to
  /// [deviceId], assigning fresh client sequences and stable operation IDs.
  /// Returns the pending operations after reassignment, in push order.
  Future<List<SyncOperation>> reassignPendingOperations({
    required String deviceId,
  });

  /// Last change-log cursor applied for [userId]; 0 before the first pull.
  Future<int> getSyncCursor(String userId);

  /// Applies pulled changes and stores [nextCursor] in one transaction, as
  /// required by the synchronization protocol. Changes referencing articles
  /// that are not stored locally are skipped; the cursor still advances.
  Future<void> applyRemoteChanges({
    required String userId,
    required List<RemoteChange> changes,
    required int nextCursor,
  });

  Future<void> close();
}
