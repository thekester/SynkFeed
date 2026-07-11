import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  test('imports and updates a feed without duplicating articles', () async {
    final repository = MemoryLocalFeedRepository();
    final fetcher = _FakeFetcher(
      const FeedDocumentResponse(body: _rss, etag: '"version-1"'),
    );
    final importer = FeedImporter(repository: repository, fetcher: fetcher);
    final url = Uri.parse('https://example.com/feed.xml');

    final first = await importer.import(url);
    final second = await importer.import(url);

    expect(first.feed.title, 'Example Feed');
    expect(first.articleCount, 1);
    expect(second.feed.id, first.feed.id);
    expect(await repository.listFeeds(), hasLength(1));
    expect(await repository.listArticles(userId: 'local-user'), hasLength(1));
    expect(fetcher.receivedEtag, '"version-1"');
  });

  test('rejects non-HTTP feed URLs before fetching', () async {
    final importer = FeedImporter(
      repository: MemoryLocalFeedRepository(),
      fetcher: _FakeFetcher(const FeedDocumentResponse(body: _rss)),
    );

    expect(
      () => importer.import(Uri.parse('file:///tmp/feed.xml')),
      throwsA(isA<FormatException>()),
    );
  });
}

class _FakeFetcher implements FeedDocumentFetcher {
  _FakeFetcher(this.response);

  final FeedDocumentResponse response;
  String? receivedEtag;

  @override
  Future<FeedDocumentResponse> fetch(
    Uri url, {
    String? etag,
    DateTime? lastModified,
  }) async {
    receivedEtag = etag;
    return response;
  }
}

const String _rss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Example Feed</title>
    <link>https://example.com</link>
    <item>
      <guid>article-1</guid>
      <title>Stored offline</title>
      <link>https://example.com/articles/1</link>
      <description>Offline article body</description>
    </item>
  </channel>
</rss>
''';
