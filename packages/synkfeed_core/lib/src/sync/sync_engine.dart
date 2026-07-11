import '../repository/local_feed_repository.dart';
import 'auth_session.dart';
import 'sync_api_client.dart';

/// The stored session is missing, expired, or tied to a revoked device.
/// The user must sign in again before synchronizing.
class SyncAuthException implements Exception {
  const SyncAuthException(this.message);

  final String message;

  @override
  String toString() => 'SyncAuthException: $message';
}

class SyncReport {
  const SyncReport({
    required this.pushedOperations,
    required this.rejectedOperations,
    required this.appliedChanges,
    required this.cursor,
  });

  final int pushedOperations;
  final int rejectedOperations;
  final int appliedChanges;
  final int cursor;
}

/// Replays local pending operations to the server and applies the server
/// change log locally, following docs/sync-protocol.md.
class SyncEngine {
  SyncEngine({
    required this.repository,
    required this.client,
    required this.sessionStore,
    this.localUserId = 'local-user',
    this.pushBatchSize = 500,
    this.pullPageSize = 200,
  });

  final LocalFeedRepository repository;
  final SyncApiClient client;
  final SessionStore sessionStore;
  final String localUserId;
  final int pushBatchSize;
  final int pullPageSize;

  AuthSession? _session;

  Future<SyncReport> synchronize() async {
    _session = await sessionStore.load();
    final session = _session;
    if (session == null) {
      throw const SyncAuthException('No active session. Sign in first.');
    }

    final operations = await repository.reassignPendingOperations(
      deviceId: session.deviceId,
    );
    var pushed = 0;
    var rejected = 0;
    for (var start = 0; start < operations.length; start += pushBatchSize) {
      final batch = operations.sublist(
        start,
        start + pushBatchSize > operations.length
            ? operations.length
            : start + pushBatchSize,
      );
      SyncPushResult result;
      try {
        result = await _authorized(
          (active) => client.push(
            accessToken: active.accessToken,
            operations: batch,
          ),
        );
      } on SyncApiException catch (error) {
        if (error.statusCode != 400) {
          rethrow;
        }
        // The server refused the whole batch (schema validation). Record the
        // rejection per operation so they stop blocking future pushes.
        for (final operation in batch) {
          await repository.markOperationRejected(
            operation.operationId,
            error.code,
          );
          rejected += 1;
        }
        continue;
      }
      for (final operationId in result.acceptedOperations) {
        await repository.acknowledgeOperation(operationId);
        pushed += 1;
      }
      for (final rejection in result.rejectedOperations) {
        await repository.markOperationRejected(
          rejection.operationId,
          rejection.code,
        );
        rejected += 1;
      }
    }

    var cursor = await repository.getSyncCursor(localUserId);
    var applied = 0;
    while (true) {
      final page = await _authorized(
        (active) => client.pull(
          accessToken: active.accessToken,
          cursor: cursor,
          limit: pullPageSize,
        ),
      );
      if (page.changes.isNotEmpty || page.nextCursor != cursor) {
        await repository.applyRemoteChanges(
          userId: localUserId,
          changes: page.changes,
          nextCursor: page.nextCursor,
        );
      }
      cursor = page.nextCursor;
      applied += page.changes.length;
      if (!page.hasMore) {
        break;
      }
    }

    return SyncReport(
      pushedOperations: pushed,
      rejectedOperations: rejected,
      appliedChanges: applied,
      cursor: cursor,
    );
  }

  Future<T> _authorized<T>(Future<T> Function(AuthSession session) action) async {
    try {
      return await action(_session!);
    } on SyncApiException catch (error) {
      if (error.statusCode == 403 && error.code == 'device_revoked') {
        await sessionStore.clear();
        throw const SyncAuthException(
          'This device was revoked. Sign in again to continue syncing.',
        );
      }
      if (error.statusCode != 401) {
        rethrow;
      }
      return action(await _refreshSession());
    }
  }

  Future<AuthSession> _refreshSession() async {
    try {
      final refreshed = await client.refresh(_session!);
      await sessionStore.save(refreshed);
      _session = refreshed;
      return refreshed;
    } on SyncApiException catch (error) {
      if (error.statusCode == 401) {
        await sessionStore.clear();
        throw const SyncAuthException(
          'The session expired. Sign in again to continue syncing.',
        );
      }
      rethrow;
    }
  }
}
