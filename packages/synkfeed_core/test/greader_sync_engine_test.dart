import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 11, 12);

  late MemoryLocalFeedRepository repository;
  late MemorySessionStore sessionStore;
  late _FakeGReaderClient client;

  setUp(() async {
    repository = MemoryLocalFeedRepository();
    sessionStore = MemorySessionStore();
    client = _FakeGReaderClient();
    await sessionStore.save(
      AuthSession(
        serverUrl: Uri.parse('https://rss.example.com'),
        accessToken: 'auth-token',
        refreshToken: '',
        deviceId: 'greader',
        email: 'dad@example.com',
        backend: SyncBackend.greader,
      ),
    );
  });

  GReaderSyncEngine engine() => GReaderSyncEngine(
    repository: repository,
    client: client,
    sessionStore: sessionStore,
  );

  test('requires a FreshRSS session', () async {
    await sessionStore.save(
      AuthSession(
        serverUrl: Uri.parse('https://other.example.com'),
        accessToken: 'a',
        refreshToken: 'r',
        deviceId: 'd',
      ),
    );
    expect(engine().synchronize(), throwsA(isA<SyncAuthException>()));
  });

  test(
    'downloads subscriptions, full articles, and reconciles states',
    () async {
      client.subscriptions = const [
        GReaderSubscription(id: 'feed/1', title: 'Example'),
      ];
      client.items = [
        GReaderItem(
          id: '42',
          title: 'Hello',
          streamId: 'feed/1',
          categories: const [],
          contentHtml: '<p>Full &amp; complete body</p>',
          publishedAt: now,
        ),
        GReaderItem(
          id: '43',
          title: 'World',
          streamId: 'feed/1',
          categories: const ['user/-/state/com.google/read'],
          contentHtml: '<p>Second body</p>',
          publishedAt: now,
        ),
      ];
      // Server truth: 42 unread + starred, 43 read.
      client.unreadIds = {'42'};
      client.starredIds = {'42'};

      final report = await engine().synchronize();

      final feeds = await repository.listFeeds();
      expect(feeds.single.id, 'greader-feed/1');
      final subscriptions = await repository.listSubscriptions(
        userId: 'local-user',
      );
      expect(subscriptions.single.feedId, 'greader-feed/1');

      final articles = await repository.listArticles(userId: 'local-user');
      expect(articles, hasLength(2));
      final hello = articles.firstWhere((a) => a.id == 'greader-42');
      expect(hello.contentHtml, contains('Full &amp; complete body'));
      expect(hello.contentText, 'Full & complete body');

      final state42 = await repository.getArticleState(
        userId: 'local-user',
        articleId: 'greader-42',
      );
      expect(state42?.isStarred, isTrue);
      expect(state42?.isRead, isFalse);
      final state43 = await repository.getArticleState(
        userId: 'local-user',
        articleId: 'greader-43',
      );
      expect(state43?.isRead, isTrue);

      // subscription + 2 articles + 2 state writes
      expect(report.appliedChanges, 5);
      expect(report.pushedOperations, 0);
    },
  );

  test('replays local read/star changes through edit-tag', () async {
    client.subscriptions = const [
      GReaderSubscription(id: 'feed/1', title: 'Example'),
    ];
    client.items = [
      GReaderItem(
        id: '42',
        title: 'Hello',
        streamId: 'feed/1',
        categories: const [],
        publishedAt: now,
      ),
    ];
    client.unreadIds = {'42'};
    await engine().synchronize();

    // The user reads the article offline.
    await repository.markArticleRead(
      userId: 'local-user',
      deviceId: 'local-device',
      clientSequence: await repository.nextClientSequence('local-device'),
      articleId: 'greader-42',
      isRead: true,
      occurredAt: now,
    );
    // Simulate the server acknowledging the read on the next pull.
    client.unreadIds = <String>{};

    final report = await engine().synchronize();

    expect(report.pushedOperations, 1);
    expect(client.editTagCalls, hasLength(1));
    final call = client.editTagCalls.single;
    expect(call.itemIds, ['42']);
    expect(call.addTag, GReaderStreams.read);
    expect(await repository.listPendingOperations(), isEmpty);
  });

  test('rejects operations that are not linked to server items', () async {
    await repository.upsertFeed(
      Feed(
        id: 'feed-local',
        canonicalUrl: Uri.parse('https://local.example.com'),
        feedUrl: Uri.parse('https://local.example.com/rss.xml'),
        title: 'Local feed',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.upsertArticles([
      Article(
        id: 'article-local',
        feedId: 'feed-local',
        externalId: 'guid',
        canonicalUrl: Uri.parse('https://local.example.com/a'),
        title: 'Local article',
        publishedAt: now,
        insertedAt: now,
      ),
    ]);
    await repository.markArticleRead(
      userId: 'local-user',
      deviceId: 'local-device',
      clientSequence: await repository.nextClientSequence('local-device'),
      articleId: 'article-local',
      isRead: true,
      occurredAt: now,
    );

    final report = await engine().synchronize();

    expect(report.rejectedOperations, 1);
    expect(client.editTagCalls, isEmpty);
    expect(await repository.listPendingOperations(), isEmpty);
  });

  test('clears the session on HTTP 401', () async {
    client.failWith = const GReaderApiException(
      statusCode: 401,
      message: 'Unauthorized',
    );

    await expectLater(
      engine().synchronize(),
      throwsA(isA<SyncAuthException>()),
    );
    expect(await sessionStore.load(), isNull);
  });
}

class _EditTagCall {
  const _EditTagCall({required this.itemIds, this.addTag, this.removeTag});

  final List<String> itemIds;
  final String? addTag;
  final String? removeTag;
}

class _FakeGReaderClient implements GReaderApiClient {
  List<GReaderSubscription> subscriptions = const [];
  List<GReaderItem> items = const [];
  Set<String> unreadIds = const {};
  Set<String> starredIds = const {};
  final List<_EditTagCall> editTagCalls = <_EditTagCall>[];
  GReaderApiException? failWith;

  void _maybeFail() {
    final error = failWith;
    if (error != null) {
      throw error;
    }
  }

  @override
  Uri get serverUrl => Uri.parse('https://rss.example.com/api/greader.php/');

  @override
  Duration get timeout => const Duration(seconds: 30);

  @override
  int get maximumResponseBytes => 20 * 1024 * 1024;

  @override
  Future<String> clientLogin({
    required String email,
    required String password,
  }) async {
    _maybeFail();
    return 'auth-token';
  }

  @override
  Future<List<GReaderSubscription>> listSubscriptions({
    required String authToken,
  }) async {
    _maybeFail();
    return subscriptions;
  }

  @override
  Future<GReaderStreamPage> streamContents({
    required String authToken,
    String streamId = GReaderStreams.readingList,
    int count = 100,
    String? continuation,
    String? excludeTarget,
  }) async {
    _maybeFail();
    return GReaderStreamPage(items: items, continuation: null);
  }

  @override
  Future<Set<String>> streamItemIds({
    required String authToken,
    required String streamId,
    String? excludeTarget,
    int count = 10000,
  }) async {
    _maybeFail();
    return streamId == GReaderStreams.starred ? starredIds : unreadIds;
  }

  @override
  Future<String> writeToken({required String authToken}) async {
    _maybeFail();
    return 'write-token';
  }

  @override
  Future<void> editTag({
    required String authToken,
    required String writeToken,
    required List<String> itemIds,
    String? addTag,
    String? removeTag,
  }) async {
    _maybeFail();
    editTagCalls.add(
      _EditTagCall(itemIds: itemIds, addTag: addTag, removeTag: removeTag),
    );
  }

  @override
  void close() {}
}
