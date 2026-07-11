import 'dart:io';

import 'package:xml/xml.dart';

import 'parsed_article.dart';
import 'parsed_feed.dart';

class RssParser {
  const RssParser();

  ParsedFeed parse(String xml, {required Uri feedUrl}) {
    final document = XmlDocument.parse(xml);
    final root = document.rootElement;

    switch (root.name.local) {
      case 'rss':
        return _parseRss(root, feedUrl);
      case 'feed':
        return _parseAtom(root, feedUrl);
      default:
        throw FormatException('Unsupported feed format: ${root.name.local}');
    }
  }

  ParsedFeed _parseRss(XmlElement root, Uri feedUrl) {
    final channel = _firstElement(root, 'channel') ?? root;
    final title = _requiredText(channel, 'title', fallback: feedUrl.host);
    final siteUrl = _parseUri(_firstText(channel, 'link'));
    final description = _firstText(channel, 'description');
    final language = _firstText(channel, 'language');

    final articles = channel.childElements
        .where((element) => element.name.local == 'item')
        .map(_parseRssItem)
        .toList(growable: false);

    return ParsedFeed(
      title: title,
      feedUrl: feedUrl,
      siteUrl: siteUrl,
      description: description,
      language: language,
      articles: articles,
    );
  }

  ParsedFeed _parseAtom(XmlElement root, Uri feedUrl) {
    final title = _requiredText(root, 'title', fallback: feedUrl.host);
    final siteUrl = _parseAtomLink(root);
    final description = _firstText(root, 'subtitle');
    final language = root.getAttribute('xml:lang') ?? root.getAttribute('lang');

    final articles = root.childElements
        .where((element) => element.name.local == 'entry')
        .map(_parseAtomEntry)
        .toList(growable: false);

    return ParsedFeed(
      title: title,
      feedUrl: feedUrl,
      siteUrl: siteUrl,
      description: description,
      language: language,
      articles: articles,
    );
  }

  ParsedArticleDraft _parseRssItem(XmlElement item) {
    final externalId =
        _firstText(item, 'guid') ??
        _firstText(item, 'link') ??
        _firstText(item, 'title') ??
        'rss-item';
    final canonicalUrl = _parseUri(_firstText(item, 'link'));
    final title = _requiredText(item, 'title', fallback: externalId);
    final summary = _firstText(item, 'description');
    final contentHtml = _firstText(item, 'encoded') ?? summary;
    final author = _firstText(item, 'author');
    final publishedAt = _parseDate(_firstText(item, 'pubDate'));

    return ParsedArticleDraft(
      externalId: externalId,
      canonicalUrl: canonicalUrl,
      title: title,
      author: author,
      summary: summary,
      contentHtml: contentHtml,
      contentText: _stripHtml(contentHtml ?? summary ?? ''),
      publishedAt: publishedAt,
      updatedAt: publishedAt,
    );
  }

  ParsedArticleDraft _parseAtomEntry(XmlElement entry) {
    final externalId =
        _firstText(entry, 'id') ??
        _firstText(entry, 'link') ??
        _firstText(entry, 'title') ??
        'atom-entry';
    final canonicalUrl = _parseAtomLink(entry);
    final title = _requiredText(entry, 'title', fallback: externalId);
    final summary = _firstText(entry, 'summary');
    final content = _firstText(entry, 'content');
    final contentText = _firstText(entry, 'content') ?? summary;
    final author = _firstText(entry, 'name', parentName: 'author');
    final updatedAt = _parseDate(
      _firstText(entry, 'updated') ?? _firstText(entry, 'published'),
    );

    return ParsedArticleDraft(
      externalId: externalId,
      canonicalUrl: canonicalUrl,
      title: title,
      author: author,
      summary: summary,
      contentHtml: content ?? summary,
      contentText: _stripHtml(contentText ?? ''),
      publishedAt: _parseDate(_firstText(entry, 'published')),
      updatedAt: updatedAt,
    );
  }

  Uri? _parseAtomLink(XmlElement parent) {
    final links = parent.childElements.where(
      (element) => element.name.local == 'link',
    );
    for (final link in links) {
      final rel = link.getAttribute('rel');
      if (rel == null || rel == 'alternate') {
        final href = link.getAttribute('href');
        final parsed = _parseUri(href);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    for (final link in links) {
      final parsed = _parseUri(link.getAttribute('href'));
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  XmlElement? _firstElement(XmlElement parent, String localName) {
    for (final element in parent.childElements) {
      if (element.name.local == localName) {
        return element;
      }
    }
    return null;
  }

  String? _firstText(
    XmlElement parent,
    String localName, {
    String? parentName,
  }) {
    Iterable<XmlElement> candidates = parent.childElements;
    if (parentName != null) {
      final parentElement = _firstElement(parent, parentName);
      if (parentElement == null) {
        return null;
      }
      candidates = parentElement.childElements;
    }

    for (final element in candidates) {
      if (element.name.local == localName) {
        return element.innerText.trim();
      }
    }
    return null;
  }

  String _requiredText(
    XmlElement parent,
    String localName, {
    required String fallback,
  }) {
    final value = _firstText(parent, localName);
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return value.trim();
  }

  Uri? _parseUri(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return Uri.tryParse(value.trim());
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final raw = value.trim();
    try {
      return HttpDate.parse(raw).toUtc();
    } catch (_) {
      return DateTime.tryParse(raw)?.toUtc();
    }
  }

  String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
