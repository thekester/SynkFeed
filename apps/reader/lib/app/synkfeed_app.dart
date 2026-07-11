import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synkfeed_core/synkfeed_core.dart';

import 'key_value_store_io.dart'
    if (dart.library.js_interop) 'key_value_store_web.dart';
import 'platform_session_store_io.dart'
    if (dart.library.js_interop) 'platform_session_store_web.dart';
import 'reader_demo_controller.dart';
import 'sync_account_controller.dart';
import 'theme_controller.dart';
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
  final ThemeController _themeController = ThemeController(
    createKeyValueStore(),
  );
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
      // the sync server; only the session and preferences survive a refresh.
      repository = widget.repository ?? MemoryLocalFeedRepository();
      sessionStore = widget.sessionStore ?? createWebSessionStore();
      await _themeController.load();
    } else if (widget.repository != null) {
      repository = widget.repository!;
      sessionStore = widget.sessionStore ?? MemorySessionStore();
      await _themeController.load();
    } else {
      final directory = await getApplicationSupportDirectory();
      final separator = Platform.pathSeparator;
      repository = SqliteLocalFeedRepository(
        '${directory.path}${separator}synkfeed.sqlite',
      );
      sessionStore =
          widget.sessionStore ??
          FileSessionStore('${directory.path}${separator}session.json');
      await _themeController.attachStore(
        createKeyValueStore(
          filePath: '${directory.path}${separator}settings.json',
        ),
      );
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
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SynkFeed',
          theme: buildSynkFeedTheme(Brightness.light),
          darkTheme: buildSynkFeedTheme(Brightness.dark),
          themeMode: _themeController.mode,
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
                themeController: _themeController,
              );
            },
          ),
        );
      },
    );
  }
}

/// Shared theme for both brightnesses: teal seed, softly rounded fields,
/// floating snackbars, and quiet chips.
ThemeData buildSynkFeedTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brightness == Brightness.light
        ? const Color(0xFF0F766E)
        : const Color(0xFF14B8A6),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      width: 480,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbVisibility: WidgetStatePropertyAll(false),
    ),
  );
}
