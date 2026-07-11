import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/article.dart';
import '../models/feed.dart';
import '../repository/local_feed_repository.dart';
import 'rss_parser.dart';

class FeedImportResult {
  const FeedImportResult({
    required this.feed,
    required this.articleCount,
    required this.notModified,
  });

  final Feed feed;
  final int articleCount;
  final bool notModified;
}

abstract class FeedDocumentFetcher {
  Future<FeedDocumentResponse> fetch(
    Uri url, {
    String? etag,
    DateTime? lastModified,
  });
}

class FeedDocumentResponse {
  const FeedDocumentResponse({
    required this.body,
    this.etag,
    this.lastModified,
    this.notModified = false,
  });

  final String body;
  final String? etag;
  final DateTime? lastModified;
  final bool notModified;
}

class HttpFeedDocumentFetcher implements FeedDocumentFetcher {
  HttpFeedDocumentFetcher({
    this.timeout = const Duration(seconds: 20),
    this.maximumResponseBytes = 5 * 1024 * 1024,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final Duration timeout;
  final int maximumResponseBytes;
  final HttpClient _client;

  @override
  Future<FeedDocumentResponse> fetch(
    Uri url, {
    String? etag,
    DateTime? lastModified,
  }) async {
    _validateHttpUrl(url);
    final request = await _client.getUrl(url).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, _acceptedFeedTypes);
    request.headers.set(HttpHeaders.userAgentHeader, 'SynkFeed/0.1');
    if (etag != null) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    if (lastModified != null) {
      request.headers.set(
        HttpHeaders.ifModifiedSinceHeader,
        HttpDate.format(lastModified.toUtc()),
      );
    }

    final response = await request.close().timeout(timeout);
    if (response.statusCode == HttpStatus.notModified) {
      await response.drain<void>();
      return FeedDocumentResponse(
        body: '',
        etag: etag,
        lastModified: lastModified,
        notModified: true,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException(
        'Feed request failed with HTTP ${response.statusCode}.',
        uri: url,
      );
    }

    final declaredLength = response.contentLength;
    if (declaredLength > maximumResponseBytes) {
      await response.drain<void>();
      throw const FormatException('Feed response is too large.');
    }

    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maximumResponseBytes) {
        throw const FormatException('Feed response is too large.');
      }
    }

    return FeedDocumentResponse(
      body: utf8.decode(bytes, allowMalformed: true),
      etag: response.headers.value(HttpHeaders.etagHeader),
      lastModified: _parseHttpDate(
        response.headers.value(HttpHeaders.lastModifiedHeader),
      ),
    );
  }
}

class FeedImporter {
  FeedImporter({
    required this.repository,
    FeedDocumentFetcher? fetcher,
    this.parser = const RssParser(),
  }) : fetcher = fetcher ?? HttpFeedDocumentFetcher();

  final LocalFeedRepository repository;
  final FeedDocumentFetcher fetcher;
  final RssParser parser;

  Future<FeedImportResult> import(Uri feedUrl) async {
    _validateHttpUrl(feedUrl);
    final existing = await _findFeed(feedUrl);
    final response = await fetcher.fetch(
      feedUrl,
      etag: existing?.etag,
      lastModified: existing?.lastModified,
    );
    final now = DateTime.now().toUtc();

    if (response.notModified && existing != null) {
      final refreshed = existing.copyWith(lastFetchedAt: now, updatedAt: now);
      await repository.upsertFeed(refreshed);
      return FeedImportResult(
        feed: refreshed,
        articleCount: 0,
        notModified: true,
      );
    }

    final parsed = parser.parse(response.body, feedUrl: feedUrl);
    final feedId = existing?.id ?? _stableId('feed', feedUrl.toString());
    final feed = Feed(
      id: feedId,
      canonicalUrl: parsed.siteUrl ?? feedUrl,
      feedUrl: feedUrl,
      siteUrl: parsed.siteUrl,
      title: parsed.title,
      description: parsed.description,
      language: parsed.language,
      etag: response.etag,
      lastModified: response.lastModified,
      lastFetchedAt: now,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final articles = parsed.articles
        .map((draft) {
          final identity = draft.externalId.isNotEmpty
              ? draft.externalId
              : (draft.canonicalUrl ?? feedUrl).toString();
          return Article(
            id: _stableId('article', '$feedId\u0000$identity'),
            feedId: feedId,
            externalId: draft.externalId,
            canonicalUrl: draft.canonicalUrl ?? feedUrl,
            title: draft.title,
            author: draft.author,
            summary: draft.summary,
            contentHtml: draft.contentHtml,
            contentText: draft.contentText,
            publishedAt: draft.publishedAt,
            updatedAt: draft.updatedAt,
            downloadedAt: now,
            contentHash: draft.contentHash,
            insertedAt: now,
          );
        })
        .toList(growable: false);

    await repository.upsertFeed(feed);
    await repository.upsertArticles(articles);
    return FeedImportResult(
      feed: feed,
      articleCount: articles.length,
      notModified: false,
    );
  }

  Future<Feed?> _findFeed(Uri url) async {
    for (final feed in await repository.listFeeds()) {
      if (feed.feedUrl == url) {
        return feed;
      }
    }
    return null;
  }
}

DateTime? _parseHttpDate(String? value) {
  if (value == null) {
    return null;
  }
  try {
    return HttpDate.parse(value).toUtc();
  } on FormatException {
    return null;
  }
}

void _validateHttpUrl(Uri url) {
  if (!url.hasScheme ||
      url.host.isEmpty ||
      (url.scheme != 'http' && url.scheme != 'https')) {
    throw const FormatException('Please provide a valid HTTP(S) feed URL.');
  }
}

String _stableId(String prefix, String value) {
  final digest = sha256.convert(utf8.encode(value)).toString();
  return '$prefix-$digest';
}

const String _acceptedFeedTypes =
    'application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.1';
