import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/remote_change.dart';
import '../models/sync_operation.dart';
import 'auth_session.dart';

/// Non-2xx response from the SynkFeed server, carrying the error `code`
/// documented by the API (`invalid_credentials`, `device_revoked`, ...).
class SyncApiException implements Exception {
  const SyncApiException({required this.statusCode, required this.code});

  final int statusCode;
  final String code;

  @override
  String toString() => 'SyncApiException($statusCode, $code)';
}

class RejectedOperation {
  const RejectedOperation({required this.operationId, required this.code});

  final String operationId;
  final String code;
}

class SyncPushResult {
  const SyncPushResult({
    required this.acceptedOperations,
    required this.rejectedOperations,
  });

  final List<String> acceptedOperations;
  final List<RejectedOperation> rejectedOperations;
}

class SyncPullPage {
  const SyncPullPage({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<RemoteChange> changes;
  final int nextCursor;
  final bool hasMore;
}

/// HTTP transport for the SynkFeed server API.
class SyncApiClient {
  SyncApiClient({
    required this.serverUrl,
    this.timeout = const Duration(seconds: 20),
    this.maximumResponseBytes = 5 * 1024 * 1024,
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient();

  final Uri serverUrl;
  final Duration timeout;
  final int maximumResponseBytes;
  final HttpClient _client;

  Future<AuthSession> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) {
    return _authenticate(
      '/v1/auth/register',
      email,
      password,
      deviceName,
      platform,
    );
  }

  Future<AuthSession> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) {
    return _authenticate(
      '/v1/auth/login',
      email,
      password,
      deviceName,
      platform,
    );
  }

  /// Exchanges the session refresh token for a rotated token pair.
  Future<AuthSession> refresh(AuthSession session) async {
    final body = await _request(
      'POST',
      '/v1/auth/refresh',
      body: <String, Object?>{'refreshToken': session.refreshToken},
    );
    return session.copyWith(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
      deviceId: body['deviceId'] as String? ?? session.deviceId,
    );
  }

  Future<SyncPushResult> push({
    required String accessToken,
    required List<SyncOperation> operations,
  }) async {
    final body = await _request(
      'POST',
      '/v1/sync/push',
      accessToken: accessToken,
      body: <String, Object?>{
        'operations': operations
            .map(
              (operation) => <String, Object?>{
                'operationId': operation.operationId,
                'deviceId': operation.deviceId,
                'clientSequence': operation.clientSequence,
                'entityType': operation.entityType,
                'entityId': operation.entityId,
                'operationType': operation.operationType,
                'payload': operation.payload,
                'createdAt': operation.createdAt.toUtc().toIso8601String(),
              },
            )
            .toList(growable: false),
      },
    );
    return SyncPushResult(
      acceptedOperations: (body['acceptedOperations'] as List? ?? const [])
          .cast<String>(),
      rejectedOperations: (body['rejectedOperations'] as List? ?? const [])
          .map(
            (entry) => RejectedOperation(
              operationId: (entry as Map)['operationId'] as String,
              code: entry['code'] as String,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<SyncPullPage> pull({
    required String accessToken,
    int cursor = 0,
    int limit = 200,
  }) async {
    final body = await _request(
      'GET',
      '/v1/sync/pull',
      accessToken: accessToken,
      query: <String, String>{'cursor': '$cursor', 'limit': '$limit'},
    );
    return SyncPullPage(
      changes: (body['changes'] as List? ?? const [])
          .map(
            (entry) =>
                RemoteChange.fromJson(Map<String, Object?>.from(entry as Map)),
          )
          .toList(growable: false),
      nextCursor: (body['nextCursor'] as num).toInt(),
      hasMore: body['hasMore'] as bool? ?? false,
    );
  }

  void close() {
    _client.close(force: true);
  }

  Future<AuthSession> _authenticate(
    String path,
    String email,
    String password,
    String deviceName,
    String platform,
  ) async {
    final body = await _request(
      'POST',
      path,
      body: <String, Object?>{
        'email': email,
        'password': password,
        'deviceName': deviceName,
        'platform': platform,
      },
    );
    return AuthSession(
      serverUrl: serverUrl,
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
      deviceId: body['deviceId'] as String,
      email: email,
    );
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    String? accessToken,
  }) async {
    final base = serverUrl.path.endsWith('/')
        ? serverUrl
        : serverUrl.replace(path: '${serverUrl.path}/');
    var url = base.resolve(path.startsWith('/') ? path.substring(1) : path);
    if (query != null) {
      url = url.replace(queryParameters: query);
    }
    final request = await _client.openUrl(method, url).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (accessToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(timeout);
    final decoded = await _decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncApiException(
        statusCode: response.statusCode,
        code: decoded['code'] as String? ?? 'http_${response.statusCode}',
      );
    }
    return decoded;
  }

  Future<Map<String, Object?>> _decodeBody(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maximumResponseBytes) {
        throw const FormatException('Server response is too large.');
      }
    }
    if (bytes.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : const <String, Object?>{};
  }
}
