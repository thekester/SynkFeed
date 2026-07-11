import 'dart:convert';
import 'dart:io';

import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late GReaderApiClient client;
  late List<_RecordedRequest> requests;

  setUp(() async {
    requests = <_RecordedRequest>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final recorded = _RecordedRequest(
        path: request.uri.path,
        query: request.uri.queryParameters,
        authorization: request.headers.value(HttpHeaders.authorizationHeader),
        body: body,
      );
      requests.add(recorded);
      final response = _respond(recorded);
      request.response.statusCode = response.statusCode;
      request.response.write(response.body);
      await request.response.close();
    });
    client = GReaderApiClient(
      serverUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('normalizes long item IDs to short decimal form', () {
    expect(
      normalizeGReaderItemId(
        'tag:google.com,2005:reader/item/000000000000002a',
      ),
      '42',
    );
    expect(normalizeGReaderItemId('12345'), '12345');
  });

  test('appends api/greader.php to a FreshRSS root URL', () async {
    await client.clientLogin(email: 'dad', password: 'api-password');
    expect(requests.single.path, '/api/greader.php/accounts/ClientLogin');
  });

  test('clientLogin parses the Auth token', () async {
    final token = await client.clientLogin(
      email: 'dad',
      password: 'api-password',
    );
    expect(token, 'dad/token123');
    expect(requests.single.body, contains('Email=dad'));
  });

  test('clientLogin surfaces HTTP 401', () {
    expect(
      client.clientLogin(email: 'dad', password: 'wrong'),
      throwsA(
        isA<GReaderApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('listSubscriptions decodes feeds', () async {
    final subscriptions = await client.listSubscriptions(authToken: 't');
    expect(requests.single.authorization, 'GoogleLogin auth=t');
    expect(subscriptions, hasLength(1));
    expect(subscriptions.single.id, 'feed/1');
    expect(subscriptions.single.title, 'Example');
    expect(subscriptions.single.url, Uri.parse('https://example.com/rss.xml'));
  });

  test('streamContents decodes items with full content and states', () async {
    final page = await client.streamContents(authToken: 't', count: 2);
    expect(page.continuation, 'page2');
    final item = page.items.single;
    expect(item.id, '42');
    expect(item.streamId, 'feed/1');
    expect(item.contentHtml, contains('Full article body'));
    expect(item.isRead, isFalse);
    expect(item.isStarred, isTrue);
    expect(item.publishedAt, DateTime.utc(2026, 7, 11, 8));
  });

  test('streamItemIds returns a normalized set', () async {
    final ids = await client.streamItemIds(
      authToken: 't',
      streamId: GReaderStreams.readingList,
      excludeTarget: GReaderStreams.read,
    );
    expect(requests.single.query['xt'], GReaderStreams.read);
    expect(ids, {'42', '43'});
  });

  test('editTag posts item IDs with the write token', () async {
    await client.editTag(
      authToken: 't',
      writeToken: 'wt',
      itemIds: const ['42'],
      addTag: GReaderStreams.read,
    );
    final request = requests.single;
    expect(request.path, endsWith('/reader/api/0/edit-tag'));
    expect(request.body, contains('i=42'));
    expect(request.body, contains('T=wt'));
    expect(
      request.body,
      contains('a=${Uri.encodeQueryComponent(GReaderStreams.read)}'),
    );
  });
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.query,
    required this.authorization,
    required this.body,
  });

  final String path;
  final Map<String, String> query;
  final String? authorization;
  final String body;
}

class _StubResponse {
  const _StubResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

_StubResponse _respond(_RecordedRequest request) {
  final path = request.path;
  if (path.endsWith('/accounts/ClientLogin')) {
    if (request.body.contains('Passwd=wrong')) {
      return const _StubResponse(401, 'Unauthorized');
    }
    return const _StubResponse(200, 'SID=sid\nLSID=lsid\nAuth=dad/token123\n');
  }
  if (path.endsWith('/subscription/list')) {
    return _StubResponse(
      200,
      jsonEncode({
        'subscriptions': [
          {
            'id': 'feed/1',
            'title': 'Example',
            'url': 'https://example.com/rss.xml',
            'htmlUrl': 'https://example.com',
            'iconUrl': 'https://example.com/favicon.ico',
          },
        ],
      }),
    );
  }
  if (path.contains('/stream/contents/')) {
    return _StubResponse(
      200,
      jsonEncode({
        'continuation': 'page2',
        'items': [
          {
            'id': 'tag:google.com,2005:reader/item/000000000000002a',
            'title': 'Hello',
            'published':
                DateTime.utc(2026, 7, 11, 8).millisecondsSinceEpoch ~/ 1000,
            'author': 'Author',
            'summary': {'content': '<p>Full article body</p>'},
            'alternate': [
              {'href': 'https://example.com/articles/hello'},
            ],
            'origin': {'streamId': 'feed/1', 'title': 'Example'},
            'categories': ['user/-/state/com.google/starred'],
          },
        ],
      }),
    );
  }
  if (path.endsWith('/stream/items/ids')) {
    return _StubResponse(
      200,
      jsonEncode({
        'itemRefs': [
          {'id': '42'},
          {'id': '43'},
        ],
      }),
    );
  }
  if (path.endsWith('/reader/api/0/token')) {
    return const _StubResponse(200, 'wt');
  }
  if (path.endsWith('/reader/api/0/edit-tag')) {
    return const _StubResponse(200, 'OK');
  }
  return const _StubResponse(404, 'not found');
}
