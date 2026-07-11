import 'local_feed_repository.dart';

/// Web stand-in for the SQLite adapter, which needs `dart:ffi`.
///
/// The web build keeps its library in memory and repopulates it from the
/// synchronization server; constructing this class is a programming error.
class SqliteLocalFeedRepository implements LocalFeedRepository {
  SqliteLocalFeedRepository(String path) {
    throw UnsupportedError(_message);
  }

  SqliteLocalFeedRepository.inMemory() {
    throw UnsupportedError(_message);
  }

  static const int schemaVersion = 4;

  static const String _message =
      'SQLite storage is not available on the web; '
      'use MemoryLocalFeedRepository instead.';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(_message);
}
