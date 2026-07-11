class Subscription {
  const Subscription({
    required this.id,
    required this.userId,
    required this.feedId,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.customTitle,
    this.isMuted = false,
    this.deletedAt,
    this.syncVersion = 0,
  });

  final String id;
  final String userId;
  final String feedId;
  final String? folderId;
  final String? customTitle;
  final bool isMuted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncVersion;

  Subscription copyWith({
    String? folderId,
    Object? customTitle = _unset,
    bool? isMuted,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    int? syncVersion,
  }) {
    return Subscription(
      id: id,
      userId: userId,
      feedId: feedId,
      folderId: folderId ?? this.folderId,
      customTitle: identical(customTitle, _unset)
          ? this.customTitle
          : customTitle as String?,
      isMuted: isMuted ?? this.isMuted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _unset)
          ? this.deletedAt
          : deletedAt as DateTime?,
      syncVersion: syncVersion ?? this.syncVersion,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'user_id': userId,
    'feed_id': feedId,
    'folder_id': folderId,
    'custom_title': customTitle,
    'is_muted': isMuted,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'sync_version': syncVersion,
  };

  static Subscription fromMap(Map<String, Object?> map) => Subscription(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    feedId: map['feed_id'] as String,
    folderId: map['folder_id'] as String?,
    customTitle: map['custom_title'] as String?,
    isMuted: map['is_muted'] as bool? ?? false,
    createdAt: _date(map['created_at'])!,
    updatedAt: _date(map['updated_at'])!,
    deletedAt: _date(map['deleted_at']),
    syncVersion: map['sync_version'] as int? ?? 0,
  );

  static DateTime? _date(Object? value) {
    final raw = value as String?;
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }
}

const Object _unset = Object();
