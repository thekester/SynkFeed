import 'package:xml/xml.dart';

class OpmlEntry {
  const OpmlEntry({
    required this.title,
    required this.feedUrl,
    this.siteUrl,
    this.folderPath = const <String>[],
  });

  final String title;
  final Uri feedUrl;
  final Uri? siteUrl;
  final List<String> folderPath;
}

class OpmlDocument {
  const OpmlDocument(this.entries);

  final List<OpmlEntry> entries;

  static OpmlDocument parse(String source) {
    final document = XmlDocument.parse(source);
    if (document.rootElement.name.local.toLowerCase() != 'opml') {
      throw const FormatException('The selected file is not an OPML document.');
    }
    final body = document.rootElement.childElements
        .where((element) => element.name.local.toLowerCase() == 'body')
        .firstOrNull;
    if (body == null) {
      throw const FormatException('The OPML document has no body.');
    }

    final entries = <OpmlEntry>[];
    for (final outline in body.childElements.where(_isOutline)) {
      _readOutline(outline, const <String>[], entries);
    }
    return OpmlDocument(List<OpmlEntry>.unmodifiable(entries));
  }

  String encode({String title = 'SynkFeed subscriptions'}) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'opml',
      attributes: <String, String>{'version': '2.0'},
      nest: () {
        builder.element(
          'head',
          nest: () => builder.element('title', nest: title),
        );
        builder.element('body', nest: () => _writeEntries(builder, entries));
      },
    );
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  static void _readOutline(
    XmlElement outline,
    List<String> folderPath,
    List<OpmlEntry> entries,
  ) {
    final xmlUrl = outline.getAttribute('xmlUrl');
    final children = outline.childElements.where(_isOutline).toList();
    final label =
        outline.getAttribute('text') ?? outline.getAttribute('title') ?? '';

    if (xmlUrl != null) {
      final feedUrl = Uri.tryParse(xmlUrl.trim());
      if (feedUrl != null &&
          feedUrl.host.isNotEmpty &&
          (feedUrl.scheme == 'http' || feedUrl.scheme == 'https')) {
        entries.add(
          OpmlEntry(
            title: label.trim().isEmpty ? feedUrl.host : label.trim(),
            feedUrl: feedUrl,
            siteUrl: _httpUri(outline.getAttribute('htmlUrl')),
            folderPath: List<String>.unmodifiable(folderPath),
          ),
        );
      }
    }

    final nextPath = xmlUrl == null && label.trim().isNotEmpty
        ? <String>[...folderPath, label.trim()]
        : folderPath;
    for (final child in children) {
      _readOutline(child, nextPath, entries);
    }
  }

  static void _writeEntries(XmlBuilder builder, List<OpmlEntry> entries) {
    final grouped = <String, List<OpmlEntry>>{};
    for (final entry in entries) {
      final folder = entry.folderPath.isEmpty ? '' : entry.folderPath.first;
      grouped.putIfAbsent(folder, () => <OpmlEntry>[]).add(entry);
    }
    for (final group in grouped.entries) {
      void writeGroup() {
        for (final entry in group.value) {
          builder.element(
            'outline',
            attributes: <String, String>{
              'type': 'rss',
              'text': entry.title,
              'title': entry.title,
              'xmlUrl': entry.feedUrl.toString(),
              if (entry.siteUrl != null) 'htmlUrl': entry.siteUrl.toString(),
            },
          );
        }
      }

      if (group.key.isEmpty) {
        writeGroup();
      } else {
        builder.element(
          'outline',
          attributes: <String, String>{'text': group.key},
          nest: writeGroup,
        );
      }
    }
  }
}

bool _isOutline(XmlElement element) =>
    element.name.local.toLowerCase() == 'outline';

Uri? _httpUri(String? value) {
  final uri = value == null ? null : Uri.tryParse(value.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}
