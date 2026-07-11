import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../models/article.dart';
import '../models/article_state.dart';
import '../models/feed.dart';
import '../models/remote_change.dart';
import '../models/retention_policy.dart';
import '../models/sync_operation.dart';
import '../models/subscription.dart';
import 'local_feed_repository.dart';

class SqliteLocalFeedRepository implements LocalFeedRepository {
  SqliteLocalFeedRepository(String path) : _database = sqlite3.open(path) {
    _migrate();
  }

  SqliteLocalFeedRepository.inMemory() : _database = sqlite3.openInMemory() {
    _migrate();
  }

  static const int schemaVersion = 4;

  final Database _database;
  bool _closed = false;

  @override
  Future<void> upsertFeed(Feed feed) async {
    final values = feed.toMap();
    _database.execute('''
      INSERT INTO feeds (
        id, canonical_url, feed_url, site_url, title, description, language,
        icon_url, local_icon_path, etag, last_modified, last_fetched_at,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        canonical_url = excluded.canonical_url,
        feed_url = excluded.feed_url,
        site_url = excluded.site_url,
        title = excluded.title,
        description = excluded.description,
        language = excluded.language,
        icon_url = excluded.icon_url,
        local_icon_path = excluded.local_icon_path,
        etag = excluded.etag,
        last_modified = excluded.last_modified,
        last_fetched_at = excluded.last_fetched_at,
        updated_at = excluded.updated_at
    ''', _parameters(values, _feedColumns));
  }

  @override
  Future<void> upsertArticles(Iterable<Article> articles) async {
    _transaction(() {
      for (final article in articles) {
        final values = article.toMap();
        _database.execute('''
          INSERT INTO articles (
            id, feed_id, external_id, canonical_url, title, author, summary,
            content_html, content_text, published_at, updated_at, downloaded_at,
            estimated_reading_time_micros, content_hash, inserted_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            feed_id = excluded.feed_id,
            external_id = excluded.external_id,
            canonical_url = excluded.canonical_url,
            title = excluded.title,
            author = excluded.author,
            summary = excluded.summary,
            content_html = excluded.content_html,
            content_text = excluded.content_text,
            published_at = excluded.published_at,
            updated_at = excluded.updated_at,
            downloaded_at = excluded.downloaded_at,
            estimated_reading_time_micros = excluded.estimated_reading_time_micros,
            content_hash = excluded.content_hash
        ''', _parameters(values, _articleColumns));
      }
    });
  }

  @override
  Future<List<Feed>> listFeeds() async {
    final rows = _database.select(
      'SELECT * FROM feeds ORDER BY title COLLATE NOCASE, id',
    );
    return rows.map((row) => Feed.fromMap(_rowMap(row))).toList();
  }

  @override
  Future<void> upsertSubscription(Subscription subscription) async {
    final values = subscription.toMap();
    _database.execute(
      '''
      INSERT INTO subscriptions (
        id, user_id, feed_id, folder_id, custom_title, is_muted, created_at,
        updated_at, deleted_at, sync_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        folder_id = excluded.folder_id,
        custom_title = excluded.custom_title,
        is_muted = excluded.is_muted,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        sync_version = excluded.sync_version
    ''',
      <Object?>[
        values['id'],
        values['user_id'],
        values['feed_id'],
        values['folder_id'],
        values['custom_title'],
        subscription.isMuted ? 1 : 0,
        values['created_at'],
        values['updated_at'],
        values['deleted_at'],
        values['sync_version'],
      ],
    );
  }

  @override
  Future<List<Subscription>> listSubscriptions({required String userId}) async {
    final rows = _database.select(
      '''
      SELECT * FROM subscriptions
      WHERE user_id = ? AND deleted_at IS NULL
      ORDER BY created_at, id
    ''',
      <Object?>[userId],
    );
    return rows.map((row) {
      final map = _rowMap(row);
      map['is_muted'] = (map['is_muted'] as int) != 0;
      return Subscription.fromMap(map);
    }).toList();
  }

  @override
  Future<void> deleteSubscription({
    required String subscriptionId,
    required DateTime deletedAt,
  }) async {
    _database.execute(
      '''
      UPDATE subscriptions
      SET deleted_at = ?, updated_at = ?, sync_version = sync_version + 1
      WHERE id = ?
    ''',
      <Object?>[
        deletedAt.toUtc().toIso8601String(),
        deletedAt.toUtc().toIso8601String(),
        subscriptionId,
      ],
    );
  }

  @override
  Future<RetentionPolicy> getRetentionPolicy(String userId) async {
    final rows = _database.select(
      'SELECT * FROM retention_policies WHERE user_id = ?',
      <Object?>[userId],
    );
    if (rows.isEmpty) {
      return const RetentionPolicy();
    }
    final row = rows.single;
    return RetentionPolicy(
      retentionDays: row['retention_days'] as int?,
      maximumArticlesPerFeed: row['maximum_articles_per_feed'] as int?,
      maximumCacheBytes: row['maximum_cache_bytes'] as int,
      downloadImages: (row['download_images'] as int) != 0,
      imagesOnWifiOnly: (row['images_on_wifi_only'] as int) != 0,
      preserveUnread: (row['preserve_unread'] as int) != 0,
      preserveStarred: (row['preserve_starred'] as int) != 0,
    );
  }

  @override
  Future<void> saveRetentionPolicy(
    String userId,
    RetentionPolicy policy,
  ) async {
    _database.execute(
      '''
      INSERT INTO retention_policies (
        user_id, retention_days, maximum_articles_per_feed,
        maximum_cache_bytes, download_images, images_on_wifi_only,
        preserve_unread, preserve_starred
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        retention_days = excluded.retention_days,
        maximum_articles_per_feed = excluded.maximum_articles_per_feed,
        maximum_cache_bytes = excluded.maximum_cache_bytes,
        download_images = excluded.download_images,
        images_on_wifi_only = excluded.images_on_wifi_only,
        preserve_unread = excluded.preserve_unread,
        preserve_starred = excluded.preserve_starred
    ''',
      <Object?>[
        userId,
        policy.retentionDays,
        policy.maximumArticlesPerFeed,
        policy.maximumCacheBytes,
        policy.downloadImages ? 1 : 0,
        policy.imagesOnWifiOnly ? 1 : 0,
        policy.preserveUnread ? 1 : 0,
        policy.preserveStarred ? 1 : 0,
      ],
    );
  }

  @override
  Future<int> cleanUpArticles({
    required String userId,
    required DateTime now,
  }) async {
    final policy = await getRetentionPolicy(userId);
    if (policy.retentionDays == null && policy.maximumArticlesPerFeed == null) {
      return 0;
    }
    final removalReasons = <String>[];
    final parameters = <Object?>[userId];
    if (policy.retentionDays != null) {
      removalReasons.add("COALESCE(published_at, inserted_at) < ?");
      parameters.add(
        now
            .toUtc()
            .subtract(Duration(days: policy.retentionDays!))
            .toIso8601String(),
      );
    }
    if (policy.maximumArticlesPerFeed != null) {
      removalReasons.add('article_rank > ?');
      parameters.add(policy.maximumArticlesPerFeed);
    }
    final protections = <String>[];
    if (policy.preserveUnread) {
      protections.add('is_read = 1');
    }
    if (policy.preserveStarred) {
      protections.add('is_starred = 0');
    }
    final eligibility = protections.isEmpty
        ? ''
        : 'AND ${protections.join(' AND ')}';

    _database.execute('''
      WITH ranked AS (
        SELECT
          a.id,
          a.published_at,
          a.inserted_at,
          COALESCE(s.is_read, 0) AS is_read,
          COALESCE(s.is_starred, 0) AS is_starred,
          ROW_NUMBER() OVER (
            PARTITION BY a.feed_id
            ORDER BY COALESCE(a.published_at, a.inserted_at) DESC, a.id
          ) AS article_rank
        FROM articles a
        LEFT JOIN article_states s
          ON s.article_id = a.id AND s.user_id = ?
      )
      DELETE FROM articles
      WHERE id IN (
        SELECT id FROM ranked
        WHERE (${removalReasons.join(' OR ')}) $eligibility
      )
    ''', parameters);
    return _database.updatedRows;
  }

  @override
  Future<List<Article>> listArticles({
    required String userId,
    String? feedId,
    bool unreadOnly = false,
    bool starredOnly = false,
    String? searchQuery,
  }) async {
    final clauses = <String>[];
    final parameters = <Object?>[];
    if (feedId != null) {
      clauses.add('a.feed_id = ?');
      parameters.add(feedId);
    }
    if (unreadOnly) {
      clauses.add('COALESCE(s.is_read, 0) = 0');
    }
    if (starredOnly) {
      clauses.add('COALESCE(s.is_starred, 0) = 1');
    }
    final normalizedQuery = searchQuery?.trim();
    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      clauses.add('INSTR(LOWER(a.title), LOWER(?)) > 0');
      parameters.add(normalizedQuery);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = _database.select(
      '''
      SELECT a.* FROM articles a
      LEFT JOIN article_states s
        ON s.article_id = a.id AND s.user_id = ?
      $where
      ORDER BY COALESCE(a.published_at, '') DESC, a.title COLLATE NOCASE
    ''',
      <Object?>[userId, ...parameters],
    );
    return rows.map((row) => Article.fromMap(_rowMap(row))).toList();
  }

  @override
  Future<ArticleState?> getArticleState({
    required String userId,
    required String articleId,
  }) async {
    final rows = _database.select(
      'SELECT * FROM article_states WHERE user_id = ? AND article_id = ?',
      <Object?>[userId, articleId],
    );
    return rows.isEmpty ? null : _articleStateFromRow(rows.first);
  }

  @override
  Future<ArticleState> upsertArticleState(ArticleState state) async {
    _upsertArticleState(state);
    return state;
  }

  @override
  Future<int> nextClientSequence(String deviceId) async {
    return _transaction(() {
      _database.execute(
        '''
        INSERT INTO client_sequences (device_id, last_sequence)
        VALUES (?, 1)
        ON CONFLICT(device_id) DO UPDATE SET
          last_sequence = last_sequence + 1
      ''',
        <Object?>[deviceId],
      );
      return _database.select(
            'SELECT last_sequence FROM client_sequences WHERE device_id = ?',
            <Object?>[deviceId],
          ).single['last_sequence']
          as int;
    });
  }

  @override
  Future<SyncOperation?> markArticleRead({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required bool isRead,
    DateTime? occurredAt,
  }) async {
    return _writeState(
      userId: userId,
      deviceId: deviceId,
      clientSequence: clientSequence,
      articleId: articleId,
      operationType: 'mark_read',
      value: isRead,
      occurredAt: occurredAt,
      read: true,
    );
  }

  @override
  Future<SyncOperation?> toggleArticleStar({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required bool isStarred,
    DateTime? occurredAt,
  }) async {
    return _writeState(
      userId: userId,
      deviceId: deviceId,
      clientSequence: clientSequence,
      articleId: articleId,
      operationType: 'toggle_star',
      value: isStarred,
      occurredAt: occurredAt,
      read: false,
    );
  }

  @override
  Future<List<SyncOperation>> listPendingOperations() async {
    final rows = _database.select('''
      SELECT * FROM sync_operations
      WHERE status = 'pending'
      ORDER BY client_sequence, created_at, operation_id
    ''');
    return rows.map(_syncOperationFromRow).toList();
  }

  @override
  Future<void> acknowledgeOperation(String operationId) async {
    _database.execute(
      "UPDATE sync_operations SET status = 'acknowledged' WHERE operation_id = ?",
      <Object?>[operationId],
    );
  }

  @override
  Future<void> markOperationRejected(String operationId, String errorCode) async {
    _database.execute(
      '''
      UPDATE sync_operations
      SET status = 'rejected', error_code = ?
      WHERE operation_id = ?
    ''',
      <Object?>[errorCode, operationId],
    );
  }

  @override
  Future<List<SyncOperation>> reassignPendingOperations({
    required String deviceId,
  }) async {
    _transaction(() {
      final rows = _database.select(
        '''
        SELECT operation_id, entity_id, operation_type FROM sync_operations
        WHERE status = 'pending' AND device_id != ?
        ORDER BY client_sequence, created_at, operation_id
      ''',
        <Object?>[deviceId],
      );
      for (final row in rows) {
        _database.execute(
          '''
          INSERT INTO client_sequences (device_id, last_sequence)
          VALUES (?, 1)
          ON CONFLICT(device_id) DO UPDATE SET
            last_sequence = last_sequence + 1
        ''',
          <Object?>[deviceId],
        );
        final sequence =
            _database.select(
                  'SELECT last_sequence FROM client_sequences WHERE device_id = ?',
                  <Object?>[deviceId],
                ).single['last_sequence']
                as int;
        final operationId =
            '$deviceId:${row['entity_id']}:$sequence:${row['operation_type']}';
        _database.execute(
          '''
          UPDATE sync_operations
          SET operation_id = ?, device_id = ?, client_sequence = ?
          WHERE operation_id = ?
        ''',
          <Object?>[operationId, deviceId, sequence, row['operation_id']],
        );
      }
    });
    return listPendingOperations();
  }

  @override
  Future<int> getSyncCursor(String userId) async {
    final rows = _database.select(
      'SELECT last_cursor FROM sync_state WHERE user_id = ?',
      <Object?>[userId],
    );
    return rows.isEmpty ? 0 : rows.single['last_cursor'] as int;
  }

  @override
  Future<void> applyRemoteChanges({
    required String userId,
    required List<RemoteChange> changes,
    required int nextCursor,
  }) async {
    _transaction(() {
      for (final change in changes) {
        final state = change.toArticleState(userId);
        if (state == null) {
          continue;
        }
        final known = _database.select(
          'SELECT 1 FROM articles WHERE id = ?',
          <Object?>[state.articleId],
        );
        if (known.isEmpty) {
          continue;
        }
        _upsertArticleState(state);
      }
      _database.execute(
        '''
        INSERT INTO sync_state (user_id, last_cursor)
        VALUES (?, ?)
        ON CONFLICT(user_id) DO UPDATE SET last_cursor = excluded.last_cursor
      ''',
        <Object?>[userId, nextCursor],
      );
    });
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      _database.close();
    }
  }

  SyncOperation? _writeState({
    required String userId,
    required String deviceId,
    required int clientSequence,
    required String articleId,
    required String operationType,
    required bool value,
    required DateTime? occurredAt,
    required bool read,
  }) {
    return _transaction(() {
      final rows = _database.select(
        'SELECT * FROM article_states WHERE user_id = ? AND article_id = ?',
        <Object?>[userId, articleId],
      );
      final current = rows.isEmpty
          ? ArticleState(
              userId: userId,
              articleId: articleId,
              isRead: false,
              isStarred: false,
              isArchived: false,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              logicalVersion: 0,
            )
          : _articleStateFromRow(rows.first);
      if ((read ? current.isRead : current.isStarred) == value) {
        return null;
      }

      final effectiveAt = occurredAt ?? DateTime.now().toUtc();
      final updated = read
          ? current.markRead(value, at: effectiveAt)
          : current.markStarred(value, at: effectiveAt);
      final operation = SyncOperation(
        operationId: '$deviceId:$articleId:$clientSequence:$operationType',
        deviceId: deviceId,
        entityType: 'article_state',
        entityId: articleId,
        operationType: operationType,
        payload: read
            ? <String, Object?>{'isRead': value}
            : <String, Object?>{'isStarred': value},
        clientSequence: clientSequence,
        createdAt: effectiveAt,
      );

      _upsertArticleState(updated);
      _insertOperation(operation);
      return operation;
    });
  }

  void _upsertArticleState(ArticleState state) {
    final values = state.toMap();
    _database.execute(
      '''
      INSERT INTO article_states (
        user_id, article_id, is_read, read_at, is_starred, starred_at,
        is_archived, updated_at, logical_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, article_id) DO UPDATE SET
        is_read = excluded.is_read,
        read_at = excluded.read_at,
        is_starred = excluded.is_starred,
        starred_at = excluded.starred_at,
        is_archived = excluded.is_archived,
        updated_at = excluded.updated_at,
        logical_version = excluded.logical_version
    ''',
      <Object?>[
        values['user_id'],
        values['article_id'],
        state.isRead ? 1 : 0,
        values['read_at'],
        state.isStarred ? 1 : 0,
        values['starred_at'],
        state.isArchived ? 1 : 0,
        values['updated_at'],
        values['logical_version'],
      ],
    );
  }

  void _insertOperation(SyncOperation operation) {
    _database.execute(
      '''
      INSERT OR IGNORE INTO sync_operations (
        operation_id, device_id, entity_type, entity_id, operation_type,
        payload_json, client_sequence, created_at, attempt_count,
        last_attempt_at, status, error_code
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      <Object?>[
        operation.operationId,
        operation.deviceId,
        operation.entityType,
        operation.entityId,
        operation.operationType,
        jsonEncode(operation.payload),
        operation.clientSequence,
        operation.createdAt.toUtc().toIso8601String(),
        operation.attemptCount,
        operation.lastAttemptAt?.toUtc().toIso8601String(),
        operation.status,
        operation.errorCode,
      ],
    );
  }

  ArticleState _articleStateFromRow(Row row) {
    final map = _rowMap(row);
    map['is_read'] = (map['is_read'] as int) != 0;
    map['is_starred'] = (map['is_starred'] as int) != 0;
    map['is_archived'] = (map['is_archived'] as int) != 0;
    return ArticleState.fromMap(map);
  }

  SyncOperation _syncOperationFromRow(Row row) {
    final map = _rowMap(row);
    final decoded = jsonDecode(map['payload_json'] as String);
    map['payload_json'] = Map<String, Object?>.from(decoded as Map);
    return SyncOperation.fromMap(map);
  }

  T _transaction<T>(T Function() action) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _migrate() {
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('PRAGMA journal_mode = WAL');
    var currentVersion =
        _database.select('PRAGMA user_version').single['user_version'] as int;
    if (currentVersion > schemaVersion) {
      throw StateError(
        'Database schema $currentVersion is newer than supported schema $schemaVersion.',
      );
    }
    if (currentVersion == 0) {
      _transaction(() {
        _database.execute(_initialSchema);
        _database.execute('PRAGMA user_version = 1');
      });
      currentVersion = 1;
    }
    if (currentVersion == 1) {
      _transaction(() {
        _database.execute(_subscriptionsSchema);
        _database.execute('PRAGMA user_version = 2');
      });
      currentVersion = 2;
    }
    if (currentVersion == 2) {
      _transaction(() {
        _database.execute(_retentionPolicySchema);
        _database.execute('PRAGMA user_version = 3');
      });
      currentVersion = 3;
    }
    if (currentVersion == 3) {
      _transaction(() {
        _database.execute(_syncStateSchema);
        _database.execute('PRAGMA user_version = 4');
      });
    }
  }
}

Map<String, Object?> _rowMap(Row row) => Map<String, Object?>.fromEntries(
  row.keys.map((key) => MapEntry<String, Object?>(key, row[key])),
);

List<Object?> _parameters(Map<String, Object?> values, List<String> columns) =>
    columns.map((column) => values[column]).toList(growable: false);

const List<String> _feedColumns = <String>[
  'id',
  'canonical_url',
  'feed_url',
  'site_url',
  'title',
  'description',
  'language',
  'icon_url',
  'local_icon_path',
  'etag',
  'last_modified',
  'last_fetched_at',
  'created_at',
  'updated_at',
];

const List<String> _articleColumns = <String>[
  'id',
  'feed_id',
  'external_id',
  'canonical_url',
  'title',
  'author',
  'summary',
  'content_html',
  'content_text',
  'published_at',
  'updated_at',
  'downloaded_at',
  'estimated_reading_time_micros',
  'content_hash',
  'inserted_at',
];

const String _initialSchema = '''
  CREATE TABLE feeds (
    id TEXT PRIMARY KEY,
    canonical_url TEXT NOT NULL,
    feed_url TEXT NOT NULL UNIQUE,
    site_url TEXT,
    title TEXT NOT NULL,
    description TEXT,
    language TEXT,
    icon_url TEXT,
    local_icon_path TEXT,
    etag TEXT,
    last_modified TEXT,
    last_fetched_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

  CREATE TABLE articles (
    id TEXT PRIMARY KEY,
    feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
    external_id TEXT NOT NULL,
    canonical_url TEXT NOT NULL,
    title TEXT NOT NULL,
    author TEXT,
    summary TEXT,
    content_html TEXT,
    content_text TEXT,
    published_at TEXT,
    updated_at TEXT,
    downloaded_at TEXT,
    estimated_reading_time_micros INTEGER,
    content_hash TEXT,
    inserted_at TEXT NOT NULL,
    UNIQUE(feed_id, external_id)
  );

  CREATE INDEX articles_feed_published
    ON articles(feed_id, published_at DESC);

  CREATE TABLE article_states (
    user_id TEXT NOT NULL,
    article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    is_read INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0, 1)),
    read_at TEXT,
    is_starred INTEGER NOT NULL DEFAULT 0 CHECK(is_starred IN (0, 1)),
    starred_at TEXT,
    is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN (0, 1)),
    updated_at TEXT NOT NULL,
    logical_version INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(user_id, article_id)
  );

  CREATE INDEX article_states_filters
    ON article_states(user_id, is_read, is_starred);

  CREATE TABLE sync_operations (
    operation_id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation_type TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    client_sequence INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_attempt_at TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    error_code TEXT
  );

  CREATE INDEX sync_operations_pending
    ON sync_operations(status, client_sequence);

  CREATE TABLE client_sequences (
    device_id TEXT PRIMARY KEY,
    last_sequence INTEGER NOT NULL
  );
''';

const String _subscriptionsSchema = '''
  CREATE TABLE subscriptions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
    folder_id TEXT,
    custom_title TEXT,
    is_muted INTEGER NOT NULL DEFAULT 0 CHECK(is_muted IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(user_id, feed_id)
  );

  CREATE INDEX subscriptions_user_active
    ON subscriptions(user_id, deleted_at, created_at);

  INSERT INTO subscriptions (
    id, user_id, feed_id, created_at, updated_at, sync_version
  )
  SELECT
    'subscription-' || id, 'local-user', id, created_at, updated_at, 0
  FROM feeds;
''';

const String _syncStateSchema = '''
  CREATE TABLE sync_state (
    user_id TEXT PRIMARY KEY,
    last_cursor INTEGER NOT NULL DEFAULT 0
  );
''';

const String _retentionPolicySchema = '''
  CREATE TABLE retention_policies (
    user_id TEXT PRIMARY KEY,
    retention_days INTEGER CHECK(retention_days IS NULL OR retention_days > 0),
    maximum_articles_per_feed INTEGER
      CHECK(maximum_articles_per_feed IS NULL OR maximum_articles_per_feed > 0),
    maximum_cache_bytes INTEGER NOT NULL CHECK(maximum_cache_bytes > 0),
    download_images INTEGER NOT NULL CHECK(download_images IN (0, 1)),
    images_on_wifi_only INTEGER NOT NULL CHECK(images_on_wifi_only IN (0, 1)),
    preserve_unread INTEGER NOT NULL CHECK(preserve_unread IN (0, 1)),
    preserve_starred INTEGER NOT NULL CHECK(preserve_starred IN (0, 1))
  );
''';
