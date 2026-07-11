import 'article_state.dart';

/// One entry of the server change log, as returned by `GET /v1/sync/pull`.
class RemoteChange {
  const RemoteChange({
    required this.cursor,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.data,
  });

  final int cursor;
  final String entityType;
  final String entityId;
  final String operationType;
  final Map<String, Object?> data;

  static RemoteChange fromJson(Map<String, Object?> json) {
    final data = json['data'];
    return RemoteChange(
      cursor: _asInt(json['cursor']),
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      operationType: json['operationType'] as String,
      data: data is Map
          ? Map<String, Object?>.from(data)
          : <String, Object?>{},
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cursor': cursor,
      'entityType': entityType,
      'entityId': entityId,
      'operationType': operationType,
      'data': data,
    };
  }

  /// Converts an `article_state` change into a local [ArticleState].
  ///
  /// Returns null for entity types this client does not track yet.
  ArticleState? toArticleState(String userId) {
    if (entityType != 'article_state') {
      return null;
    }
    return ArticleState(
      userId: userId,
      articleId: entityId,
      isRead: _asBool(data['is_read']),
      readAt: _asDate(data['read_at']),
      isStarred: _asBool(data['is_starred']),
      starredAt: _asDate(data['starred_at']),
      isArchived: _asBool(data['is_archived']),
      updatedAt: _asDate(data['updated_at']) ?? DateTime.now().toUtc(),
      logicalVersion: _asInt(data['logical_version']),
    );
  }
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  return false;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

DateTime? _asDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}
