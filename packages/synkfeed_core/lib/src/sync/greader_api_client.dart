import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Google Reader stream and tag identifiers used by FreshRSS.
class GReaderStreams {
  static const String readingList = 'user/-/state/com.google/reading-list';
  static const String read = 'user/-/state/com.google/read';
  static const String starred = 'user/-/state/com.google/starred';
}

/// Non-2xx response from a Google Reader-compatible endpoint.
class GReaderApiException implements Exception {
  const GReaderApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  @override
  String toString() => 'GReaderApiException($statusCode, $message)';
}

class GReaderSubscription {
  const GReaderSubscription({
    required this.id,
    required this.title,
    this.url,
    this.htmlUrl,
    this.iconUrl,
  });

  /// Stream identifier, e.g. `feed/12` on FreshRSS.
  final String id;
  final String title;
  final Uri? url;
  final Uri? htmlUrl;
  final Uri? iconUrl;
}

class GReaderItem {
  const GReaderItem({
    required this.id,
    required this.title,
    required this.streamId,
    required this.categories,
    this.author,
    this.contentHtml,
    this.url,
    this.publishedAt,
  });

  /// Short decimal item ID (normalized from the long
  /// `tag:google.com,2005:reader/item/<hex>` form when needed).
  final String id;
  final String title;
  final String streamId;
  final List<String> categories;
  final String? author;
  final String? contentHtml;
  final Uri? url;
  final DateTime? publishedAt;

  bool get isRead =>
      categories.any((category) => category.endsWith('/state/com.google/read'));

  bool get isStarred => categories.any(
    (category) => category.endsWith('/state/com.google/starred'),
  );
}

class GReaderStreamPage {
  const GReaderStreamPage({required this.items, this.continuation});

  final List<GReaderItem> items;
  final String? continuation;
}

/// Normalizes a Google Reader item ID to its short decimal form.
///
/// `tag:google.com,2005:reader/item/000000000000002a` becomes `42`; short
/// decimal IDs pass through unchanged.
String normalizeGReaderItemId(String id) {
  const prefix = 'tag:google.com,2005:reader/item/';
  if (!id.startsWith(prefix)) {
    return id;
  }
  final hex = id.substring(prefix.length);
  final value = BigInt.tryParse(hex, radix: 16);
  return value == null ? id : value.toString();
}

/// Client for the Google Reader-compatible API served by FreshRSS.
///
/// [serverUrl] is the FreshRSS root URL (e.g. `https://rss.example.com`); the
/// standard `api/greader.php` suffix is appended unless already present.
class GReaderApiClient {
  GReaderApiClient({
    required Uri serverUrl,
    this.timeout = const Duration(seconds: 30),
    this.maximumResponseBytes = 20 * 1024 * 1024,
    HttpClient? httpClient,
  }) : serverUrl = _apiRoot(serverUrl),
       _client = httpClient ?? HttpClient();

  final Uri serverUrl;
  final Duration timeout;
  final int maximumResponseBytes;
  final HttpClient _client;

  /// Exchanges the account email and API password for a long-lived
  /// `GoogleLogin` auth token.
  Future<String> clientLogin({
    required String email,
    required String password,
  }) async {
    final body = await _request(
      'POST',
      'accounts/ClientLogin',
      form: <String, String>{'Email': email, 'Passwd': password},
    );
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('Auth=')) {
        return line.substring('Auth='.length).trim();
      }
    }
    throw const GReaderApiException(
      statusCode: 200,
      message: 'The server did not return an Auth token.',
    );
  }

  Future<List<GReaderSubscription>> listSubscriptions({
    required String authToken,
  }) async {
    final body = await _requestJson(
      'GET',
      'reader/api/0/subscription/list',
      authToken: authToken,
      query: <String, String>{'output': 'json'},
    );
    return (body['subscriptions'] as List? ?? const [])
        .map((entry) {
          final map = Map<String, Object?>.from(entry as Map);
          return GReaderSubscription(
            id: map['id'] as String,
            title: map['title'] as String? ?? map['id'] as String,
            url: _tryParseUrl(map['url']),
            htmlUrl: _tryParseUrl(map['htmlUrl']),
            iconUrl: _tryParseUrl(map['iconUrl']),
          );
        })
        .toList(growable: false);
  }

  Future<GReaderStreamPage> streamContents({
    required String authToken,
    String streamId = GReaderStreams.readingList,
    int count = 100,
    String? continuation,
    String? excludeTarget,
  }) async {
    final body = await _requestJson(
      'GET',
      'reader/api/0/stream/contents/${Uri.encodeComponent(streamId)}',
      authToken: authToken,
      query: <String, String>{
        'output': 'json',
        'n': '$count',
        'c': ?continuation,
        'xt': ?excludeTarget,
      },
    );
    final items = (body['items'] as List? ?? const [])
        .map((entry) {
          final map = Map<String, Object?>.from(entry as Map);
          final origin = map['origin'];
          final summary = map['summary'] ?? map['content'];
          final alternate = map['alternate'];
          final published = map['published'];
          return GReaderItem(
            id: normalizeGReaderItemId(map['id'] as String),
            title: map['title'] as String? ?? '(untitled)',
            streamId: origin is Map ? origin['streamId'] as String? ?? '' : '',
            categories: (map['categories'] as List? ?? const []).cast<String>(),
            author: map['author'] as String?,
            contentHtml: summary is Map ? summary['content'] as String? : null,
            url: alternate is List && alternate.isNotEmpty
                ? _tryParseUrl((alternate.first as Map)['href'])
                : null,
            publishedAt: published is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    published.toInt() * 1000,
                    isUtc: true,
                  )
                : null,
          );
        })
        .toList(growable: false);
    return GReaderStreamPage(
      items: items,
      continuation: body['continuation'] as String?,
    );
  }

  /// Returns normalized item IDs of a stream, e.g. unread or starred sets.
  Future<Set<String>> streamItemIds({
    required String authToken,
    required String streamId,
    String? excludeTarget,
    int count = 10000,
  }) async {
    final body = await _requestJson(
      'GET',
      'reader/api/0/stream/items/ids',
      authToken: authToken,
      query: <String, String>{
        'output': 'json',
        's': streamId,
        'n': '$count',
        'xt': ?excludeTarget,
      },
    );
    return (body['itemRefs'] as List? ?? const [])
        .map((entry) => normalizeGReaderItemId((entry as Map)['id'].toString()))
        .toSet();
  }

  /// Fetches the short-lived token required by write operations.
  Future<String> writeToken({required String authToken}) async {
    final body = await _request(
      'GET',
      'reader/api/0/token',
      authToken: authToken,
    );
    return body.trim();
  }

  /// Adds and/or removes a state tag (read, starred) on the given items.
  Future<void> editTag({
    required String authToken,
    required String writeToken,
    required List<String> itemIds,
    String? addTag,
    String? removeTag,
  }) async {
    final parts = <String>[
      for (final id in itemIds) 'i=${Uri.encodeQueryComponent(id)}',
      if (addTag != null) 'a=${Uri.encodeQueryComponent(addTag)}',
      if (removeTag != null) 'r=${Uri.encodeQueryComponent(removeTag)}',
      'T=${Uri.encodeQueryComponent(writeToken)}',
    ];
    await _request(
      'POST',
      'reader/api/0/edit-tag',
      authToken: authToken,
      rawForm: parts.join('&'),
    );
  }

  void close() {
    _client.close(force: true);
  }

  Future<Map<String, Object?>> _requestJson(
    String method,
    String path, {
    Map<String, String>? query,
    String? authToken,
  }) async {
    final body = await _request(
      method,
      path,
      query: query,
      authToken: authToken,
    );
    if (body.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(body);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : const <String, Object?>{};
  }

  Future<String> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
    String? rawForm,
    String? authToken,
  }) async {
    var url = serverUrl.resolve(path);
    if (query != null) {
      url = url.replace(queryParameters: query);
    }
    final request = await _client.openUrl(method, url).timeout(timeout);
    if (authToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'GoogleLogin auth=$authToken',
      );
    }
    final encodedForm =
        rawForm ??
        form?.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&');
    if (encodedForm != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.add(utf8.encode(encodedForm));
    }
    final response = await request.close().timeout(timeout);
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maximumResponseBytes) {
        throw const FormatException('Server response is too large.');
      }
    }
    final body = utf8.decode(bytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GReaderApiException(
        statusCode: response.statusCode,
        message: body.length > 200 ? body.substring(0, 200) : body,
      );
    }
    return body;
  }

  static Uri _apiRoot(Uri serverUrl) {
    var path = serverUrl.path;
    if (path.contains('greader.php')) {
      // Keep an explicitly provided API endpoint as-is.
      path = path.substring(
        0,
        path.indexOf('greader.php') + 'greader.php'.length,
      );
    } else {
      if (!path.endsWith('/')) {
        path = '$path/';
      }
      path = '${path}api/greader.php';
    }
    return serverUrl.replace(path: '$path/', query: null, fragment: null);
  }
}

Uri? _tryParseUrl(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(value);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    return null;
  }
  return parsed;
}
