import 'package:web/web.dart' as web;

import 'theme_controller.dart';

/// Browser preference storage backed by localStorage.
KeyValueStore createKeyValueStore({String? filePath}) {
  return _LocalStorageKeyValueStore();
}

class _LocalStorageKeyValueStore implements KeyValueStore {
  static const String _prefix = 'synkfeed.pref.';

  @override
  Future<String?> read(String key) async {
    return web.window.localStorage.getItem('$_prefix$key');
  }

  @override
  Future<void> write(String key, String value) async {
    web.window.localStorage.setItem('$_prefix$key', value);
  }
}
