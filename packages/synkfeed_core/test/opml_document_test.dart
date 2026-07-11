import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses nested OPML folders and ignores unsafe feed URLs', () {
    final document = OpmlDocument.parse(_source);

    expect(document.entries, hasLength(2));
    expect(document.entries.first.title, 'Example Feed');
    expect(document.entries.first.folderPath, <String>['Technology']);
    expect(
      document.entries.last.feedUrl,
      Uri.parse('https://news.example.org/atom.xml'),
    );
  });

  test('exported OPML can be parsed again', () {
    final original = OpmlDocument(<OpmlEntry>[
      OpmlEntry(
        title: 'Example & News',
        feedUrl: Uri.parse('https://example.com/feed.xml'),
        siteUrl: Uri.parse('https://example.com'),
        folderPath: const <String>['News'],
      ),
    ]);

    final parsed = OpmlDocument.parse(original.encode());

    expect(parsed.entries.single.title, 'Example & News');
    expect(parsed.entries.single.folderPath, <String>['News']);
  });
}

const String _source = '''
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head><title>Subscriptions</title></head>
  <body>
    <outline text="Technology">
      <outline type="rss" text="Example Feed"
        xmlUrl="https://example.com/feed.xml" htmlUrl="https://example.com" />
      <outline type="rss" text="Unsafe" xmlUrl="file:///tmp/feed.xml" />
    </outline>
    <outline type="rss" text="News"
      xmlUrl="https://news.example.org/atom.xml" />
  </body>
</opml>
''';
