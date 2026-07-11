import 'package:flutter/material.dart';

import 'reader_demo_controller.dart';
import '../features/home/home_screen.dart';

class SynkFeedApp extends StatefulWidget {
  const SynkFeedApp({super.key});

  @override
  State<SynkFeedApp> createState() => _SynkFeedAppState();
}

class _SynkFeedAppState extends State<SynkFeedApp> {
  late final ReaderDemoController _controller;
  late final Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    _controller = ReaderDemoController();
    _bootstrap = _controller.bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
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
          return HomeScreen(controller: _controller);
        },
      ),
    );
  }
}
