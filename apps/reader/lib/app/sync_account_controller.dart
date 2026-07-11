import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:synkfeed_core/synkfeed_core.dart';

/// Holds the server account state and drives push/pull synchronization.
class SyncAccountController extends ChangeNotifier {
  SyncAccountController({
    required this.repository,
    required this.sessionStore,
    SyncApiClient Function(Uri serverUrl)? clientFactory,
    GReaderApiClient Function(Uri serverUrl)? greaderClientFactory,
  }) : _clientFactory =
           clientFactory ??
           ((serverUrl) => SyncApiClient(serverUrl: serverUrl)),
       _greaderClientFactory =
           greaderClientFactory ??
           ((serverUrl) => GReaderApiClient(serverUrl: serverUrl));

  final LocalFeedRepository repository;
  final SessionStore sessionStore;
  final SyncApiClient Function(Uri serverUrl) _clientFactory;
  final GReaderApiClient Function(Uri serverUrl) _greaderClientFactory;

  AuthSession? _session;
  bool _isBusy = false;
  String? _lastError;
  SyncReport? _lastReport;
  DateTime? _lastSyncAt;

  AuthSession? get session => _session;
  bool get isSignedIn => _session != null;
  bool get isBusy => _isBusy;
  String? get lastError => _lastError;
  SyncReport? get lastReport => _lastReport;
  DateTime? get lastSyncAt => _lastSyncAt;

  Future<void> initialize() async {
    _session = await sessionStore.load();
    notifyListeners();
  }

  Future<void> signIn({
    required String serverUrl,
    required String email,
    required String password,
    required bool createAccount,
    SyncBackend backend = SyncBackend.synkfeed,
  }) async {
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Please provide a valid HTTP(S) server URL.');
    }
    _setBusy(true);
    try {
      final session = backend == SyncBackend.greader
          ? await _signInGReader(uri, email.trim(), password)
          : await _signInSynkFeed(uri, email.trim(), password, createAccount);
      await sessionStore.save(session);
      _session = session;
      _lastError = null;
    } on Object catch (error) {
      _lastError = describeError(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<AuthSession> _signInSynkFeed(
    Uri uri,
    String email,
    String password,
    bool createAccount,
  ) async {
    final client = _clientFactory(uri);
    try {
      return createAccount
          ? await client.register(
              email: email,
              password: password,
              deviceName: _deviceName,
              platform: _platform,
            )
          : await client.login(
              email: email,
              password: password,
              deviceName: _deviceName,
              platform: _platform,
            );
    } finally {
      client.close();
    }
  }

  Future<AuthSession> _signInGReader(
    Uri uri,
    String email,
    String password,
  ) async {
    final client = _greaderClientFactory(uri);
    try {
      final authToken = await client.clientLogin(
        email: email,
        password: password,
      );
      return AuthSession(
        serverUrl: uri,
        accessToken: authToken,
        refreshToken: '',
        deviceId: 'greader',
        email: email,
        backend: SyncBackend.greader,
      );
    } finally {
      client.close();
    }
  }

  Future<SyncReport?> syncNow() async {
    final session = _session;
    if (session == null || _isBusy) {
      return null;
    }
    _setBusy(true);
    final isGReader = session.backend == SyncBackend.greader;
    final greaderClient = isGReader
        ? _greaderClientFactory(session.serverUrl)
        : null;
    final client = isGReader ? null : _clientFactory(session.serverUrl);
    try {
      final report = isGReader
          ? await GReaderSyncEngine(
              repository: repository,
              client: greaderClient!,
              sessionStore: sessionStore,
            ).synchronize()
          : await SyncEngine(
              repository: repository,
              client: client!,
              sessionStore: sessionStore,
            ).synchronize();
      _session = await sessionStore.load();
      _lastReport = report;
      _lastSyncAt = DateTime.now().toUtc();
      _lastError = null;
      return report;
    } on Object catch (error) {
      // Refresh failures and revoked devices clear the stored session.
      _session = await sessionStore.load();
      _lastError = describeError(error);
      rethrow;
    } finally {
      client?.close();
      greaderClient?.close();
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await sessionStore.clear();
    _session = null;
    _lastReport = null;
    _lastSyncAt = null;
    _lastError = null;
    notifyListeners();
  }

  static String describeError(Object error) {
    if (error is SyncAuthException) {
      return error.message;
    }
    if (error is FormatException) {
      return error.message;
    }
    if (error is GReaderApiException) {
      return switch (error.statusCode) {
        401 || 403 =>
          'FreshRSS refused the credentials. Use your API password '
              '(Settings > Profile > API management).',
        _ => 'The FreshRSS server replied with HTTP ${error.statusCode}.',
      };
    }
    if (error is SyncApiException) {
      return switch (error.code) {
        'invalid_credentials' => 'Email or password is incorrect.',
        'email_already_registered' =>
          'An account already exists for this email.',
        'invalid_request' =>
          'The server rejected the request. Check the server version.',
        _ => 'The server replied with an error (${error.code}).',
      };
    }
    return 'Unable to reach the server. Check the URL and your connection.';
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  String get _deviceName {
    if (kIsWeb) {
      return 'Web browser';
    }
    final host = Platform.localHostname.trim();
    return host.isEmpty ? 'SynkFeed device' : host;
  }

  String get _platform {
    if (kIsWeb) {
      // The server only knows the shipped device platforms.
      return 'linux';
    }
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    return 'linux';
  }
}
