import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'repository stores feeds and queues pending operations deterministically',
    () async {
      final repository = MemoryLocalFeedRepository();
      final now = DateTime.utc(2026, 7, 11, 12, 0, 0);

      final feed = Feed(
        id: 'feed-1',
        canonicalUrl: Uri.parse('https://example.com'),
        feedUrl: Uri.parse('https://example.com/rss.xml'),
        siteUrl: Uri.parse('https://example.com'),
        title: 'Example Feed',
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
        updatedAt: now,
        insertedAt: now,
      );

      await repository.upsertFeed(feed);
      await repository.upsertArticles([article]);

      final operation = await repository.markArticleRead(
        userId: 'user-1',
        deviceId: 'device-1',
        clientSequence: 1,
        articleId: article.id,
        isRead: true,
        occurredAt: now,
      );

      expect(operation, isNotNull);
      expect(operation!.operationType, 'mark_read');

      final repeatedOperation = await repository.markArticleRead(
        userId: 'user-1',
        deviceId: 'device-1',
        clientSequence: 2,
        articleId: article.id,
        isRead: true,
        occurredAt: now,
      );

      expect(repeatedOperation, isNull);

      final state = await repository.getArticleState(
        userId: 'user-1',
        articleId: article.id,
      );
      expect(state?.isRead, isTrue);
      expect(state?.logicalVersion, 1);

      final pending = await repository.listPendingOperations();
      expect(pending, hasLength(1));

      final articles = await repository.listArticles(userId: 'user-1');
      expect(articles.single.title, 'First article');
    },
  );

  test('star updates are tracked independently from read state', () async {
    final repository = MemoryLocalFeedRepository();
    final now = DateTime.utc(2026, 7, 11, 12, 0, 0);

    final article = Article(
      id: 'article-2',
      feedId: 'feed-1',
      externalId: 'guid-2',
      canonicalUrl: Uri.parse('https://example.com/articles/2'),
      title: 'Second article',
      publishedAt: now,
      updatedAt: now,
      insertedAt: now,
    );

    await repository.upsertArticles([article]);

    final starOperation = await repository.toggleArticleStar(
      userId: 'user-1',
      deviceId: 'device-1',
      clientSequence: 3,
      articleId: article.id,
      isStarred: true,
      occurredAt: now,
    );

    expect(starOperation, isNotNull);
    expect(starOperation!.operationType, 'toggle_star');

    final state = await repository.getArticleState(
      userId: 'user-1',
      articleId: article.id,
    );
    expect(state?.isStarred, isTrue);
    expect(state?.isRead, isFalse);
  });
}
