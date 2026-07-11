import 'dart:convert';
import 'dart:io';

/// Credentials for one authenticated device on a SynkFeed server.
class AuthSession {
  const AuthSession({
    required this.serverUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
    this.email,
  });

  final Uri serverUrl;
  final String accessToken;
  final String refreshToken;
  final String deviceId;
  final String? email;

  AuthSession copyWith({
    Uri? serverUrl,
    String? accessToken,
    String? refreshToken,
    String? deviceId,
    String? email,
  }) {
    return AuthSession(
      serverUrl: serverUrl ?? this.serverUrl,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      deviceId: deviceId ?? this.deviceId,
      email: email ?? this.email,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'server_url': serverUrl.toString(),
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'device_id': deviceId,
      'email': email,
    };
  }

  static AuthSession fromJson(Map<String, Object?> json) {
    return AuthSession(
      serverUrl: Uri.parse(json['server_url'] as String),
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      deviceId: json['device_id'] as String,
      email: json['email'] as String?,
    );
  }
}

abstract class SessionStore {
  Future<AuthSession?> load();

  Future<void> save(AuthSession session);

  Future<void> clear();
}

class MemorySessionStore implements SessionStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> load() async => _session;

  @override
  Future<void> save(AuthSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

/// Persists the session as a JSON file readable only by the current user
/// profile. A missing or corrupt file simply reads as "signed out".
class FileSessionStore implements SessionStore {
  FileSessionStore(String path) : _file = File(path);

  final File _file;

  @override
  Future<AuthSession?> load() async {
    try {
      if (!await _file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return AuthSession.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on IOException {
      return null;
    }
  }

  @override
  Future<void> save(AuthSession session) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(session.toJson()), flush: true);
  }

  @override
  Future<void> clear() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}
