class ArticleState {
  const ArticleState({
    required this.userId,
    required this.articleId,
    required this.isRead,
    required this.isStarred,
    required this.isArchived,
    required this.updatedAt,
    required this.logicalVersion,
    this.readAt,
    this.starredAt,
  });

  final String userId;
  final String articleId;
  final bool isRead;
  final DateTime? readAt;
  final bool isStarred;
  final DateTime? starredAt;
  final bool isArchived;
  final DateTime updatedAt;
  final int logicalVersion;

  ArticleState copyWith({
    String? userId,
    String? articleId,
    bool? isRead,
    Object? readAt = _unset,
    bool? isStarred,
    Object? starredAt = _unset,
    bool? isArchived,
    DateTime? updatedAt,
    int? logicalVersion,
  }) {
    return ArticleState(
      userId: userId ?? this.userId,
      articleId: articleId ?? this.articleId,
      isRead: isRead ?? this.isRead,
      readAt: identical(readAt, _unset) ? this.readAt : readAt as DateTime?,
      isStarred: isStarred ?? this.isStarred,
      starredAt: identical(starredAt, _unset)
          ? this.starredAt
          : starredAt as DateTime?,
      isArchived: isArchived ?? this.isArchived,
      updatedAt: updatedAt ?? this.updatedAt,
      logicalVersion: logicalVersion ?? this.logicalVersion,
    );
  }

  ArticleState markRead(bool value, {DateTime? at}) {
    final effectiveAt = at ?? DateTime.now().toUtc();
    return copyWith(
      isRead: value,
      readAt: value ? effectiveAt : null,
      updatedAt: effectiveAt,
      logicalVersion: logicalVersion + 1,
    );
  }

  ArticleState markStarred(bool value, {DateTime? at}) {
    final effectiveAt = at ?? DateTime.now().toUtc();
    return copyWith(
      isStarred: value,
      starredAt: value ? effectiveAt : null,
      updatedAt: effectiveAt,
      logicalVersion: logicalVersion + 1,
    );
  }

  ArticleState archive(bool value, {DateTime? at}) {
    final effectiveAt = at ?? DateTime.now().toUtc();
    return copyWith(
      isArchived: value,
      updatedAt: effectiveAt,
      logicalVersion: logicalVersion + 1,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'user_id': userId,
      'article_id': articleId,
      'is_read': isRead,
      'read_at': readAt?.toUtc().toIso8601String(),
      'is_starred': isStarred,
      'starred_at': starredAt?.toUtc().toIso8601String(),
      'is_archived': isArchived,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'logical_version': logicalVersion,
    };
  }

  static ArticleState fromMap(Map<String, Object?> map) {
    return ArticleState(
      userId: map['user_id'] as String,
      articleId: map['article_id'] as String,
      isRead: map['is_read'] as bool? ?? false,
      readAt: _parseDate(map['read_at']),
      isStarred: map['is_starred'] as bool? ?? false,
      starredAt: _parseDate(map['starred_at']),
      isArchived: map['is_archived'] as bool? ?? false,
      updatedAt:
          _parseDate(map['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      logicalVersion: map['logical_version'] as int? ?? 0,
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}

const Object _unset = Object();
