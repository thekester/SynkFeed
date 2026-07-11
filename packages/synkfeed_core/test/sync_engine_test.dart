import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 11, 12, 0, 0);

  late MemoryLocalFeedRepository repository;
  late MemorySessionStore sessionStore;
  late _FakeSyncApiClient client;

  AuthSession session() => AuthSession(
    serverUrl: Uri.parse('http://localhost:8080'),
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
    deviceId: 'device-uuid',
    email: 'reader@example.com',
  );

  Future<void> seedArticle(String articleId) async {
    await repository.upsertFeed(
      Feed(
        id: 'feed-1',
        canonicalUrl: Uri.parse('https://example.com'),
        feedUrl: Uri.parse('https://example.com/rss.xml'),
        title: 'Example Feed',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.upsertArticles([
      Article(
        id: articleId,
        feedId: 'feed-1',
        externalId: 'guid-$articleId',
        canonicalUrl: Uri.parse('https://example.com/$articleId'),
        title: 'Article $articleId',
        publishedAt: now,
        updatedAt: now,
        insertedAt: now,
      ),
    ]);
  }

  setUp(() async {
    repository = MemoryLocalFeedRepository();
    sessionStore = MemorySessionStore();
    client = _FakeSyncApiClient();
    await sessionStore.save(session());
  });

  SyncEngine engine() => SyncEngine(
    repository: repository,
    client: client,
    sessionStore: sessionStore,
  );

  test('synchronize requires an active session', () async {
    await sessionStore.clear();
    expect(engine().synchronize(), throwsA(isA<SyncAuthException>()));
  });

  test(
    'pushes rebound operations, records rejections, and applies pulled pages',
    () async {
      await seedArticle('article-1');
      await seedArticle('article-2');
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

      client.pushResults.add((operations) {
        return SyncPushResult(
          acceptedOperations: [operations.first.operationId],
          rejectedOperations: [
            RejectedOperation(
              operationId: operations.last.operationId,
              code: 'article_not_found',
            ),
          ],
        );
      });
      client.pullPages.addAll([
        SyncPullPage(
          changes: [
            RemoteChange(
              cursor: 1,
              entityType: 'article_state',
              entityId: 'article-2',
              operationType: 'toggle_star',
              data: const {
                'is_read': true,
                'read_at': '2026-07-11T10:00:00.000Z',
                'is_starred': true,
                'starred_at': '2026-07-11T10:00:00.000Z',
                'is_archived': false,
                'logical_version': 5,
              },
            ),
          ],
          nextCursor: 1,
          hasMore: true,
        ),
        SyncPullPage(
          changes: [
            RemoteChange(
              cursor: 2,
              entityType: 'article_state',
              entityId: 'unknown-article',
              operationType: 'mark_read',
              data: const {'is_read': true},
            ),
          ],
          nextCursor: 2,
          hasMore: false,
        ),
      ]);

      final report = await engine().synchronize();

      // Both operations were rebound to the authenticated device.
      final pushedBatch = client.pushedBatches.single;
      expect(pushedBatch.map((op) => op.deviceId).toSet(), {'device-uuid'});
      expect(pushedBatch.map((op) => op.clientSequence).toList(), [1, 2]);

      expect(report.pushedOperations, 1);
      expect(report.rejectedOperations, 1);
      expect(report.appliedChanges, 2);
      expect(report.cursor, 2);
      expect(await repository.listPendingOperations(), isEmpty);
      expect(await repository.getSyncCursor('local-user'), 2);

      final state = await repository.getArticleState(
        userId: 'local-user',
        articleId: 'article-2',
      );
      expect(state?.isRead, isTrue);
      expect(state?.isStarred, isTrue);
      expect(state?.logicalVersion, 5);
    },
  );

  test('refreshes the session once after a 401 and retries', () async {
    client.failNextPullWith(
      const SyncApiException(statusCode: 401, code: 'invalid_token'),
    );
    client.refreshResult = (current) => current.copyWith(
      accessToken: 'access-2',
      refreshToken: 'refresh-2',
    );
    client.pullPages.add(
      const SyncPullPage(changes: [], nextCursor: 0, hasMore: false),
    );

    final report = await engine().synchronize();

    expect(report.appliedChanges, 0);
    expect(client.pullTokens, ['access-1', 'access-2']);
    final stored = await sessionStore.load();
    expect(stored?.accessToken, 'access-2');
    expect(stored?.refreshToken, 'refresh-2');
  });

  test('clears the session when the refresh token is rejected', () async {
    client.failNextPullWith(
      const SyncApiException(statusCode: 401, code: 'invalid_token'),
    );
    client.refreshError = const SyncApiException(
      statusCode: 401,
      code: 'invalid_refresh_token',
    );

    await expectLater(
      engine().synchronize(),
      throwsA(isA<SyncAuthException>()),
    );
    expect(await sessionStore.load(), isNull);
  });

  test('clears the session when the device is revoked', () async {
    client.failNextPullWith(
      const SyncApiException(statusCode: 403, code: 'device_revoked'),
    );

    await expectLater(
      engine().synchronize(),
      throwsA(isA<SyncAuthException>()),
    );
    expect(await sessionStore.load(), isNull);
  });

  test('marks a whole batch rejected when the server refuses it', () async {
    await seedArticle('article-1');
    await repository.markArticleRead(
      userId: 'local-user',
      deviceId: 'local-device',
      clientSequence: await repository.nextClientSequence('local-device'),
      articleId: 'article-1',
      isRead: true,
      occurredAt: now,
    );
    client.pushError = const SyncApiException(
      statusCode: 400,
      code: 'invalid_request',
    );
    client.pullPages.add(
      const SyncPullPage(changes: [], nextCursor: 0, hasMore: false),
    );

    final report = await engine().synchronize();

    expect(report.pushedOperations, 0);
    expect(report.rejectedOperations, 1);
    expect(await repository.listPendingOperations(), isEmpty);
  });
}

typedef _PushHandler =
    SyncPushResult Function(List<SyncOperation> operations);

class _FakeSyncApiClient implements SyncApiClient {
  final List<_PushHandler> pushResults = <_PushHandler>[];
  final List<SyncPullPage> pullPages = <SyncPullPage>[];
  final List<List<SyncOperation>> pushedBatches = <List<SyncOperation>>[];
  final List<String> pullTokens = <String>[];

  SyncApiException? pushError;
  SyncApiException? refreshError;
  AuthSession Function(AuthSession current)? refreshResult;
  SyncApiException? _nextPullError;

  void failNextPullWith(SyncApiException error) {
    _nextPullError = error;
  }

  @override
  Uri get serverUrl => Uri.parse('http://localhost:8080');

  @override
  Duration get timeout => const Duration(seconds: 20);

  @override
  int get maximumResponseBytes => 5 * 1024 * 1024;

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    final error = refreshError;
    if (error != null) {
      throw error;
    }
    final handler = refreshResult;
    if (handler == null) {
      throw StateError('Unexpected refresh call.');
    }
    return handler(session);
  }

  @override
  Future<SyncPushResult> push({
    required String accessToken,
    required List<SyncOperation> operations,
  }) async {
    pushedBatches.add(operations);
    final error = pushError;
    if (error != null) {
      throw error;
    }
    if (pushResults.isEmpty) {
      return SyncPushResult(
        acceptedOperations: operations
            .map((operation) => operation.operationId)
            .toList(growable: false),
        rejectedOperations: const [],
      );
    }
    return pushResults.removeAt(0)(operations);
  }

  @override
  Future<SyncPullPage> pull({
    required String accessToken,
    int cursor = 0,
    int limit = 200,
  }) async {
    pullTokens.add(accessToken);
    final error = _nextPullError;
    if (error != null) {
      _nextPullError = null;
      throw error;
    }
    if (pullPages.isEmpty) {
      return SyncPullPage(changes: const [], nextCursor: cursor, hasMore: false);
    }
    return pullPages.removeAt(0);
  }

  @override
  void close() {}
}
