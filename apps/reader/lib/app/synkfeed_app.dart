import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synkfeed_core/synkfeed_core.dart';

import 'platform_session_store_io.dart'
    if (dart.library.js_interop) 'platform_session_store_web.dart';
import 'reader_demo_controller.dart';
import 'sync_account_controller.dart';
import '../features/home/home_screen.dart';

class SynkFeedApp extends StatefulWidget {
  const SynkFeedApp({super.key, this.repository, this.sessionStore});

  final LocalFeedRepository? repository;
  final SessionStore? sessionStore;

  @override
  State<SynkFeedApp> createState() => _SynkFeedAppState();
}

class _SynkFeedAppState extends State<SynkFeedApp> {
  ReaderDemoController? _controller;
  SyncAccountController? _syncController;
  late final Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = _initialize();
  }

  Future<void> _initialize() async {
    LocalFeedRepository repository;
    SessionStore sessionStore;
    if (kIsWeb) {
      // The browser build keeps articles in memory and repopulates them from
      // the sync server; only the session survives a page refresh.
      repository = widget.repository ?? MemoryLocalFeedRepository();
      sessionStore = widget.sessionStore ?? createWebSessionStore();
    } else if (widget.repository != null) {
      repository = widget.repository!;
      sessionStore = widget.sessionStore ?? MemorySessionStore();
    } else {
      final directory = await getApplicationSupportDirectory();
      final separator = Platform.pathSeparator;
      repository = SqliteLocalFeedRepository(
        '${directory.path}${separator}synkfeed.sqlite',
      );
      sessionStore =
          widget.sessionStore ??
          FileSessionStore('${directory.path}${separator}session.json');
    }
    final syncController = SyncAccountController(
      repository: repository,
      sessionStore: sessionStore,
    );
    _syncController = syncController;
    await syncController.initialize();
    final controller = ReaderDemoController(repository: repository);
    _controller = controller;
    await controller.bootstrap();
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.repository.close());
      controller.dispose();
    }
    _syncController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF14B8A6),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SynkFeed',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: FutureBuilder<void>(
        future: _bootstrap,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading offline library...'),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError ||
              _controller == null ||
              _syncController == null) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to open the offline library.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return HomeScreen(
            controller: _controller!,
            syncController: _syncController!,
          );
        },
      ),
    );
  }
}
