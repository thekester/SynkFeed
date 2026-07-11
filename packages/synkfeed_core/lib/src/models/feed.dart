class Feed {
  const Feed({
    required this.id,
    required this.canonicalUrl,
    required this.feedUrl,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.siteUrl,
    this.description,
    this.language,
    this.iconUrl,
    this.localIconPath,
    this.etag,
    this.lastModified,
    this.lastFetchedAt,
  });

  final String id;
  final Uri canonicalUrl;
  final Uri feedUrl;
  final Uri? siteUrl;
  final String title;
  final String? description;
  final String? language;
  final Uri? iconUrl;
  final String? localIconPath;
  final String? etag;
  final DateTime? lastModified;
  final DateTime? lastFetchedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Feed copyWith({
    String? id,
    Uri? canonicalUrl,
    Uri? feedUrl,
    Uri? siteUrl,
    String? title,
    String? description,
    String? language,
    Uri? iconUrl,
    String? localIconPath,
    String? etag,
    DateTime? lastModified,
    DateTime? lastFetchedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Feed(
      id: id ?? this.id,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      feedUrl: feedUrl ?? this.feedUrl,
      siteUrl: siteUrl ?? this.siteUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      language: language ?? this.language,
      iconUrl: iconUrl ?? this.iconUrl,
      localIconPath: localIconPath ?? this.localIconPath,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'canonical_url': canonicalUrl.toString(),
      'feed_url': feedUrl.toString(),
      'site_url': siteUrl?.toString(),
      'title': title,
      'description': description,
      'language': language,
      'icon_url': iconUrl?.toString(),
      'local_icon_path': localIconPath,
      'etag': etag,
      'last_modified': lastModified?.toUtc().toIso8601String(),
      'last_fetched_at': lastFetchedAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  static Feed fromMap(Map<String, Object?> map) {
    return Feed(
      id: map['id'] as String,
      canonicalUrl: Uri.parse(map['canonical_url'] as String),
      feedUrl: Uri.parse(map['feed_url'] as String),
      siteUrl: _parseUri(map['site_url']),
      title: map['title'] as String,
      description: map['description'] as String?,
      language: map['language'] as String?,
      iconUrl: _parseUri(map['icon_url']),
      localIconPath: map['local_icon_path'] as String?,
      etag: map['etag'] as String?,
      lastModified: _parseDate(map['last_modified']),
      lastFetchedAt: _parseDate(map['last_fetched_at']),
      createdAt:
          _parseDate(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          _parseDate(map['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static Uri? _parseUri(Object? value) {
    final raw = value as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
