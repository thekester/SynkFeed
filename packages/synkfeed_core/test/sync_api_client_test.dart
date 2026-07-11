import 'dart:convert';
import 'dart:io';

import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late SyncApiClient client;
  late List<_RecordedRequest> requests;

  setUp(() async {
    requests = <_RecordedRequest>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(
        _RecordedRequest(
          method: request.method,
          path: request.uri.path,
          query: request.uri.queryParameters,
          authorization: request.headers.value(HttpHeaders.authorizationHeader),
          body: body.isEmpty
              ? const <String, Object?>{}
              : Map<String, Object?>.from(jsonDecode(body) as Map),
        ),
      );
      final response = _respond(request.uri.path, requests.last);
      request.response.statusCode = response.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response.body));
      await request.response.close();
    });
    client = SyncApiClient(
      serverUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('login returns a session bound to the server', () async {
    final session = await client.login(
      email: 'reader@example.com',
      password: 'correct horse battery',
      deviceName: 'Laptop',
      platform: 'linux',
    );

    expect(session.accessToken, 'access-1');
    expect(session.refreshToken, 'refresh-1');
    expect(session.deviceId, 'device-1');
    expect(session.email, 'reader@example.com');
    expect(session.serverUrl.port, server.port);
    expect(requests.single.body['deviceName'], 'Laptop');
  });

  test('login failure surfaces the server error code', () {
    expect(
      client.login(
        email: 'reader@example.com',
        password: 'wrong password!!',
        deviceName: 'Laptop',
        platform: 'linux',
      ),
      throwsA(
        isA<SyncApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.code, 'code', 'invalid_credentials'),
      ),
    );
  });

  test('refresh rotates the token pair and keeps session identity', () async {
    final session = AuthSession(
      serverUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      accessToken: 'stale-access',
      refreshToken: 'refresh-1',
      deviceId: 'device-1',
      email: 'reader@example.com',
    );

    final refreshed = await client.refresh(session);

    expect(refreshed.accessToken, 'access-2');
    expect(refreshed.refreshToken, 'refresh-2');
    expect(refreshed.deviceId, 'device-1');
    expect(refreshed.email, 'reader@example.com');
    expect(requests.single.body['refreshToken'], 'refresh-1');
  });

  test('push sends bearer token and decodes accept/reject lists', () async {
    final result = await client.push(
      accessToken: 'access-1',
      operations: <SyncOperation>[
        SyncOperation(
          operationId: 'device-1:article-a:1:mark_read',
          deviceId: 'device-1',
          entityType: 'article_state',
          entityId: 'article-a',
          operationType: 'mark_read',
          payload: const <String, Object?>{'isRead': true},
          clientSequence: 1,
          createdAt: DateTime.utc(2026, 7, 11),
        ),
      ],
    );

    expect(requests.single.authorization, 'Bearer access-1');
    final sent = (requests.single.body['operations'] as List).single as Map;
    expect(sent['operationId'], 'device-1:article-a:1:mark_read');
    expect(sent['clientSequence'], 1);
    expect(result.acceptedOperations, ['device-1:article-a:1:mark_read']);
    expect(result.rejectedOperations.single.operationId, 'other-op');
    expect(result.rejectedOperations.single.code, 'article_not_found');
  });

  test('pull decodes change pages with cursor and hasMore', () async {
    final page = await client.pull(accessToken: 'access-1', cursor: 5, limit: 2);

    expect(requests.single.query, {'cursor': '5', 'limit': '2'});
    expect(page.nextCursor, 7);
    expect(page.hasMore, isTrue);
    expect(page.changes, hasLength(2));
    expect(page.changes.first.cursor, 6);
    expect(page.changes.first.entityType, 'article_state');
    final state = page.changes.first.toArticleState('local-user');
    expect(state, isNotNull);
    expect(state!.isRead, isTrue);
    expect(state.logicalVersion, 3);
  });

  test('keeps a server base path when resolving routes', () async {
    final scoped = SyncApiClient(
      serverUrl: Uri.parse('http://127.0.0.1:${server.port}/synkfeed'),
    );
    addTearDown(scoped.close);

    await scoped.pull(accessToken: 'access-1');

    expect(requests.single.path, '/synkfeed/v1/sync/pull');
  });
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String? authorization;
  final Map<String, Object?> body;
}

class _StubResponse {
  const _StubResponse(this.statusCode, this.body);

  final int statusCode;
  final Object body;
}

_StubResponse _respond(String path, _RecordedRequest request) {
  if (path.endsWith('/v1/auth/login')) {
    if (request.body['password'] == 'wrong password!!') {
      return const _StubResponse(401, {'code': 'invalid_credentials'});
    }
    return const _StubResponse(200, {
      'accessToken': 'access-1',
      'refreshToken': 'refresh-1',
      'deviceId': 'device-1',
    });
  }
  if (path.endsWith('/v1/auth/refresh')) {
    return const _StubResponse(200, {
      'accessToken': 'access-2',
      'refreshToken': 'refresh-2',
      'deviceId': 'device-1',
    });
  }
  if (path.endsWith('/v1/sync/push')) {
    return const _StubResponse(200, {
      'acceptedOperations': ['device-1:article-a:1:mark_read'],
      'rejectedOperations': [
        {'operationId': 'other-op', 'code': 'article_not_found'},
      ],
    });
  }
  if (path.endsWith('/v1/sync/pull')) {
    return const _StubResponse(200, {
      'changes': [
        {
          'cursor': 6,
          'entityType': 'article_state',
          'entityId': 'article-a',
          'operationType': 'mark_read',
          'data': {
            'is_read': true,
            'read_at': '2026-07-11T09:00:00.000Z',
            'is_starred': false,
            'starred_at': null,
            'is_archived': false,
            'logical_version': '3',
          },
        },
        {
          'cursor': 7,
          'entityType': 'article_state',
          'entityId': 'article-b',
          'operationType': 'toggle_star',
          'data': {
            'is_read': false,
            'read_at': null,
            'is_starred': true,
            'starred_at': '2026-07-11T09:05:00.000Z',
            'is_archived': false,
            'logical_version': 1,
          },
        },
      ],
      'nextCursor': 7,
      'hasMore': true,
    });
  }
  return const _StubResponse(404, {'code': 'not_found'});
}
