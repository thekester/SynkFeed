import 'package:flutter/material.dart';

/// Minimal string key/value persistence for UI preferences.
abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// Owns the light/dark/system preference and persists it across launches.
class ThemeController extends ChangeNotifier {
  ThemeController(this._store);

  static const String _key = 'theme_mode';

  KeyValueStore _store;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Swaps in the platform store once its location is known, then reloads.
  Future<void> attachStore(KeyValueStore store) {
    _store = store;
    return load();
  }

  Future<void> load() async {
    final raw = await _store.read(_key);
    _mode = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    await _store.write(_key, mode.name);
  }

  /// System -> light -> dark -> system.
  Future<void> cycle() {
    return setMode(switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    });
  }
}
