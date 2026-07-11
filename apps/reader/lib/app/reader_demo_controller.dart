import 'package:flutter/foundation.dart';

import 'package:synkfeed_core/synkfeed_core.dart';

class ReaderDemoController extends ChangeNotifier {
  ReaderDemoController({MemoryLocalFeedRepository? repository})
    : repository = repository ?? MemoryLocalFeedRepository();

  final MemoryLocalFeedRepository repository;
  final RssParser _parser = const RssParser();
  final String _userId = 'demo-user';
  final String _deviceId = 'demo-device';

  int _clientSequence = 0;
  bool _bootstrapped = false;

  List<Feed> _feeds = <Feed>[];
  List<Article> _articles = <Article>[];
  Map<String, ArticleState> _statesByArticleId = <String, ArticleState>{};
  List<SyncOperation> _pendingOperations = <SyncOperation>[];

  String? selectedFeedId;
  String? selectedArticleId;

  bool get isBootstrapped => _bootstrapped;
  List<Feed> get feeds => List<Feed>.unmodifiable(_feeds);
  List<Article> get articles => List<Article>.unmodifiable(_articles);
  List<SyncOperation> get pendingOperations =>
      List<SyncOperation>.unmodifiable(_pendingOperations);
  int get pendingOperationCount => _pendingOperations.length;

  Feed? get selectedFeed {
    if (selectedFeedId == null) {
      return null;
    }
    for (final feed in _feeds) {
      if (feed.id == selectedFeedId) {
        return feed;
      }
    }
    return null;
  }

  Article? get selectedArticle {
    if (selectedArticleId == null) {
      return null;
    }
    for (final article in _articles) {
      if (article.id == selectedArticleId) {
        return article;
      }
    }
    return null;
  }

  List<Article> articlesForFeed(String? feedId) {
    if (feedId == null) {
      return List<Article>.unmodifiable(_articles);
    }
    return List<Article>.unmodifiable(
      _articles.where((article) => article.feedId == feedId),
    );
  }

  ArticleState? stateFor(String articleId) => _statesByArticleId[articleId];

  bool isRead(String articleId) => stateFor(articleId)?.isRead ?? false;

  bool isStarred(String articleId) => stateFor(articleId)?.isStarred ?? false;

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;
    await _seedDemoContent();
    await reload();
    if (selectedFeedId == null && _feeds.isNotEmpty) {
      selectFeed(_feeds.first.id);
    }
    notifyListeners();
  }

  Future<void> reload() async {
    _feeds = await repository.listFeeds();
    _articles = await repository.listArticles(userId: _userId);
    _pendingOperations = await repository.listPendingOperations();

    final states = <String, ArticleState>{};
    for (final article in _articles) {
      final state = await repository.getArticleState(
        userId: _userId,
        articleId: article.id,
      );
      if (state != null) {
        states[article.id] = state;
      }
    }
    _statesByArticleId = states;
    _normalizeSelection();
    notifyListeners();
  }

  Future<void> addFeedFromUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (!uri.hasScheme && uri.host.isEmpty)) {
      throw FormatException('Please provide a valid RSS or Atom URL.');
    }

    final now = DateTime.now().toUtc();
    final id = 'manual-${_feeds.length + 1}';
    final title = uri.host.isEmpty ? uri.toString() : uri.host;

    await repository.upsertFeed(
      Feed(
        id: id,
        canonicalUrl: uri,
        feedUrl: uri,
        siteUrl: uri,
        title: title,
        description: 'Manually added feed URL',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await reload();
    selectFeed(id);
  }

  Future<void> markSelectedRead(bool value) async {
    final articleId = selectedArticleId;
    if (articleId == null) {
      return;
    }

    final operation = await repository.markArticleRead(
      userId: _userId,
      deviceId: _deviceId,
      clientSequence: ++_clientSequence,
      articleId: articleId,
      isRead: value,
      occurredAt: DateTime.now().toUtc(),
    );

    if (operation != null) {
      await reload();
    }
  }

  Future<void> toggleSelectedStar() async {
    final articleId = selectedArticleId;
    if (articleId == null) {
      return;
    }

    final operation = await repository.toggleArticleStar(
      userId: _userId,
      deviceId: _deviceId,
      clientSequence: ++_clientSequence,
      articleId: articleId,
      isStarred: !isStarred(articleId),
      occurredAt: DateTime.now().toUtc(),
    );

    if (operation != null) {
      await reload();
    }
  }

  void selectFeed(String feedId) {
    selectedFeedId = feedId;
    final feedArticles = articlesForFeed(feedId);
    selectedArticleId = feedArticles.isEmpty ? null : feedArticles.first.id;
    notifyListeners();
  }

  void selectArticle(String articleId) {
    selectedArticleId = articleId;
    notifyListeners();
  }

  Future<void> _seedDemoContent() async {
    final now = DateTime.now().toUtc();

    final rssFeed = _parser.parse(
      _demoRss,
      feedUrl: Uri.parse('https://example.com/news.xml'),
    );
    final atomFeed = _parser.parse(
      _demoAtom,
      feedUrl: Uri.parse('https://example.com/dispatch.xml'),
    );

    await _storeParsedFeed(
      feedId: 'demo-rss',
      parsedFeed: rssFeed,
      createdAt: now,
    );
    await _storeParsedFeed(
      feedId: 'demo-atom',
      parsedFeed: atomFeed,
      createdAt: now,
    );
  }

  Future<void> _storeParsedFeed({
    required String feedId,
    required ParsedFeed parsedFeed,
    required DateTime createdAt,
  }) async {
    await repository.upsertFeed(
      Feed(
        id: feedId,
        canonicalUrl: parsedFeed.siteUrl ?? parsedFeed.feedUrl,
        feedUrl: parsedFeed.feedUrl,
        siteUrl: parsedFeed.siteUrl,
        title: parsedFeed.title,
        description: parsedFeed.description,
        language: parsedFeed.language,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    final articles = <Article>[];
    for (var index = 0; index < parsedFeed.articles.length; index += 1) {
      final draft = parsedFeed.articles[index];
      articles.add(
        Article(
          id: '$feedId-${index + 1}',
          feedId: feedId,
          externalId: draft.externalId,
          canonicalUrl: draft.canonicalUrl ?? parsedFeed.feedUrl,
          title: draft.title,
          author: draft.author,
          summary: draft.summary,
          contentHtml: draft.contentHtml,
          contentText: draft.contentText,
          publishedAt: draft.publishedAt,
          updatedAt: draft.updatedAt,
          insertedAt: createdAt,
        ),
      );
    }
    await repository.upsertArticles(articles);
  }

  void _normalizeSelection() {
    if (_feeds.isEmpty) {
      selectedFeedId = null;
      selectedArticleId = null;
      return;
    }

    if (selectedFeedId == null ||
        _feeds.every((feed) => feed.id != selectedFeedId)) {
      selectedFeedId = _feeds.first.id;
    }

    final feedArticles = articlesForFeed(selectedFeedId);
    if (feedArticles.isEmpty) {
      selectedArticleId = null;
      return;
    }

    if (selectedArticleId == null ||
        feedArticles.every((article) => article.id != selectedArticleId)) {
      selectedArticleId = feedArticles.first.id;
    }
  }
}

const String _demoRss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Local-first Dispatch</title>
    <link>https://example.com</link>
    <description>Offline-ready product updates</description>
    <language>en</language>
    <item>
      <guid>dispatch-1</guid>
      <title>Shipping the offline queue</title>
      <link>https://example.com/dispatch/offline-queue</link>
      <description><![CDATA[<p>The queue persists user actions while disconnected.</p>]]></description>
      <pubDate>Wed, 10 Jul 2024 12:34:56 GMT</pubDate>
    </item>
    <item>
      <guid>dispatch-2</guid>
      <title>Deterministic conflict resolution</title>
      <link>https://example.com/dispatch/conflicts</link>
      <description><![CDATA[<p>Server acceptance order keeps sync predictable.</p>]]></description>
      <pubDate>Thu, 11 Jul 2024 08:15:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';

const String _demoAtom = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>SynkFeed Lab Notes</title>
  <subtitle>Small implementation notes</subtitle>
  <link href="https://example.com/lab/" rel="alternate" />
  <entry>
    <id>tag:example.com,2024:article-atom-1</id>
    <title>Why local-first matters</title>
    <link href="https://example.com/lab/local-first" rel="alternate" />
    <summary><![CDATA[<p>The interface must never wait for the server.</p>]]></summary>
    <updated>2024-07-10T12:34:56Z</updated>
  </entry>
</feed>
''';
