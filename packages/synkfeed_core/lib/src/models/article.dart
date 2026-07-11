class Article {
  const Article({
    required this.id,
    required this.feedId,
    required this.externalId,
    required this.canonicalUrl,
    required this.title,
    required this.insertedAt,
    this.author,
    this.summary,
    this.contentHtml,
    this.contentText,
    this.publishedAt,
    this.updatedAt,
    this.downloadedAt,
    this.estimatedReadingTime,
    this.contentHash,
  });

  final String id;
  final String feedId;
  final String externalId;
  final Uri canonicalUrl;
  final String title;
  final String? author;
  final String? summary;
  final String? contentHtml;
  final String? contentText;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final DateTime? downloadedAt;
  final Duration? estimatedReadingTime;
  final String? contentHash;
  final DateTime insertedAt;

  Article copyWith({
    String? id,
    String? feedId,
    String? externalId,
    Uri? canonicalUrl,
    String? title,
    String? author,
    String? summary,
    String? contentHtml,
    String? contentText,
    DateTime? publishedAt,
    DateTime? updatedAt,
    DateTime? downloadedAt,
    Duration? estimatedReadingTime,
    String? contentHash,
    DateTime? insertedAt,
  }) {
    return Article(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      externalId: externalId ?? this.externalId,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      title: title ?? this.title,
      author: author ?? this.author,
      summary: summary ?? this.summary,
      contentHtml: contentHtml ?? this.contentHtml,
      contentText: contentText ?? this.contentText,
      publishedAt: publishedAt ?? this.publishedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      estimatedReadingTime: estimatedReadingTime ?? this.estimatedReadingTime,
      contentHash: contentHash ?? this.contentHash,
      insertedAt: insertedAt ?? this.insertedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'feed_id': feedId,
      'external_id': externalId,
      'canonical_url': canonicalUrl.toString(),
      'title': title,
      'author': author,
      'summary': summary,
      'content_html': contentHtml,
      'content_text': contentText,
      'published_at': publishedAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'downloaded_at': downloadedAt?.toUtc().toIso8601String(),
      'estimated_reading_time_micros': estimatedReadingTime?.inMicroseconds,
      'content_hash': contentHash,
      'inserted_at': insertedAt.toUtc().toIso8601String(),
    };
  }

  static Article fromMap(Map<String, Object?> map) {
    return Article(
      id: map['id'] as String,
      feedId: map['feed_id'] as String,
      externalId: map['external_id'] as String,
      canonicalUrl: Uri.parse(map['canonical_url'] as String),
      title: map['title'] as String,
      author: map['author'] as String?,
      summary: map['summary'] as String?,
      contentHtml: map['content_html'] as String?,
      contentText: map['content_text'] as String?,
      publishedAt: _parseDate(map['published_at']),
      updatedAt: _parseDate(map['updated_at']),
      downloadedAt: _parseDate(map['downloaded_at']),
      estimatedReadingTime: _parseDurationMicros(
        map['estimated_reading_time_micros'],
      ),
      contentHash: map['content_hash'] as String?,
      insertedAt:
          _parseDate(map['inserted_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  static Duration? _parseDurationMicros(Object? value) {
    final micros = value as int?;
    if (micros == null) {
      return null;
    }
    return Duration(microseconds: micros);
  }
}
