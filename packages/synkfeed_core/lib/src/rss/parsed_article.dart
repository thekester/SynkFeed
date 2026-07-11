class ParsedArticleDraft {
  const ParsedArticleDraft({
    required this.externalId,
    required this.title,
    this.canonicalUrl,
    this.author,
    this.summary,
    this.contentHtml,
    this.contentText,
    this.publishedAt,
    this.updatedAt,
    this.contentHash,
  });

  final String externalId;
  final Uri? canonicalUrl;
  final String title;
  final String? author;
  final String? summary;
  final String? contentHtml;
  final String? contentText;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final String? contentHash;
}
