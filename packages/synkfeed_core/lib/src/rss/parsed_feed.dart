import 'parsed_article.dart';

class ParsedFeed {
  const ParsedFeed({
    required this.title,
    required this.feedUrl,
    required this.articles,
    this.siteUrl,
    this.description,
    this.language,
  });

  final String title;
  final Uri feedUrl;
  final Uri? siteUrl;
  final String? description;
  final String? language;
  final List<ParsedArticleDraft> articles;
}
