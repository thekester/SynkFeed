import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  const parser = RssParser();

  test('parses RSS 2.0 feeds', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>SynkFeed Weekly</title>
    <link>https://example.com</link>
    <description>Daily RSS news</description>
    <language>en</language>
    <item>
      <guid>article-1</guid>
      <title>Hello World</title>
      <link>https://example.com/articles/hello-world</link>
      <description><![CDATA[<p>First article</p>]]></description>
      <pubDate>Wed, 10 Jul 2024 12:34:56 GMT</pubDate>
      <author>editor@example.com</author>
    </item>
  </channel>
</rss>
''';

    final parsed = parser.parse(
      xml,
      feedUrl: Uri.parse('https://example.com/rss.xml'),
    );

    expect(parsed.title, 'SynkFeed Weekly');
    expect(parsed.siteUrl, Uri.parse('https://example.com'));
    expect(parsed.language, 'en');
    expect(parsed.articles, hasLength(1));
    expect(parsed.articles.single.externalId, 'article-1');
    expect(parsed.articles.single.title, 'Hello World');
    expect(parsed.articles.single.contentText, 'First article');
  });

  test('parses Atom feeds', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>SynkFeed Atom</title>
  <subtitle>Atom news</subtitle>
  <link href="https://example.com/" rel="alternate" />
  <entry>
    <id>tag:example.com,2024:article-2</id>
    <title>Atom Entry</title>
    <link href="https://example.com/articles/atom-entry" rel="alternate" />
    <summary><![CDATA[<p>Atom summary</p>]]></summary>
    <updated>2024-07-10T12:34:56Z</updated>
  </entry>
</feed>
''';

    final parsed = parser.parse(
      xml,
      feedUrl: Uri.parse('https://example.com/atom.xml'),
    );

    expect(parsed.title, 'SynkFeed Atom');
    expect(parsed.description, 'Atom news');
    expect(parsed.articles, hasLength(1));
    expect(parsed.articles.single.externalId, 'tag:example.com,2024:article-2');
    expect(
      parsed.articles.single.canonicalUrl,
      Uri.parse('https://example.com/articles/atom-entry'),
    );
    expect(parsed.articles.single.contentText, 'Atom summary');
  });
}
