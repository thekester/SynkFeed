import 'dart:convert';

import 'package:web/web.dart' as web;

import 'package:synkfeed_core/synkfeed_core.dart';

/// Persists the session in the browser's localStorage so a page refresh does
/// not sign the user out.
SessionStore createWebSessionStore() => _LocalStorageSessionStore();

class _LocalStorageSessionStore implements SessionStore {
  static const String _key = 'synkfeed.session';

  @override
  Future<AuthSession?> load() async {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return AuthSession.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(AuthSession session) async {
    web.window.localStorage.setItem(_key, jsonEncode(session.toJson()));
  }

  @override
  Future<void> clear() async {
    web.window.localStorage.removeItem(_key);
  }
}
