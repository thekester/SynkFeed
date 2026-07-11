import 'dart:convert';
import 'dart:io';

import 'theme_controller.dart';

/// Desktop/mobile preference storage backed by one small JSON file.
/// Falls back to memory when no file path is available (tests).
KeyValueStore createKeyValueStore({String? filePath}) {
  return filePath == null
      ? MemoryKeyValueStore()
      : _FileKeyValueStore(filePath);
}

class _FileKeyValueStore implements KeyValueStore {
  _FileKeyValueStore(String path) : _file = File(path);

  final File _file;

  @override
  Future<String?> read(String key) async {
    final values = await _load();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    final values = await _load();
    values[key] = value;
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(values), flush: true);
  }

  Future<Map<String, String>> _load() async {
    try {
      if (!await _file.exists()) {
        return <String, String>{};
      }
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map) {
        return <String, String>{};
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } on FormatException {
      return <String, String>{};
    } on IOException {
      return <String, String>{};
    }
  }
}
