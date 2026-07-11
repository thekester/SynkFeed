import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:synkfeed_core/synkfeed_core.dart';

enum ArticleFilter { all, unread, starred }

class OpmlImportReport {
  const OpmlImportReport({required this.imported, required this.failedUrls});

  final int imported;
  final List<Uri> failedUrls;
}

class ReaderDemoController extends ChangeNotifier {
  ReaderDemoController({
    required this.repository,
    FeedDocumentFetcher? feedFetcher,
  }) : _importer = FeedImporter(repository: repository, fetcher: feedFetcher);

  final LocalFeedRepository repository;
  final FeedImporter _importer;
  final String _userId = 'local-user';
  final String _deviceId = 'local-device';

  bool _bootstrapped = false;
  bool _isImporting = false;
  bool _isDemoLoading = false;

  List<Feed> _feeds = <Feed>[];
  List<Article> _articles = <Article>[];
  List<Subscription> _subscriptions = <Subscription>[];
  Map<String, ArticleState> _statesByArticleId = <String, ArticleState>{};
  List<SyncOperation> _pendingOperations = <SyncOperation>[];

  String? selectedFeedId;
  String? selectedArticleId;
  ArticleFilter articleFilter = ArticleFilter.all;
  String searchQuery = '';

  bool get isBootstrapped => _bootstrapped;
  bool get isImporting => _isImporting;
  bool get isDemoLoading => _isDemoLoading;
  List<Feed> get feeds => List<Feed>.unmodifiable(_feeds);
  List<Article> get articles => List<Article>.unmodifiable(_articles);
  List<Subscription> get subscriptions =>
      List<Subscription>.unmodifiable(_subscriptions);
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

  Subscription? subscriptionForFeed(String feedId) {
    for (final subscription in _subscriptions) {
      if (subscription.feedId == feedId) {
        return subscription;
      }
    }
    return null;
  }

  String titleForFeed(Feed feed) =>
      subscriptionForFeed(feed.id)?.customTitle ?? feed.title;

  String feedTitleById(String feedId) {
    for (final feed in _feeds) {
      if (feed.id == feedId) {
        return titleForFeed(feed);
      }
    }
    return '';
  }

  int unreadCountForFeed(String feedId) {
    var count = 0;
    for (final article in _articles) {
      if (article.feedId == feedId && !isRead(article.id)) {
        count += 1;
      }
    }
    return count;
  }

  int get totalUnreadCount {
    var count = 0;
    for (final article in _articles) {
      if (!isRead(article.id)) {
        count += 1;
      }
    }
    return count;
  }

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;
    await reload();
    notifyListeners();
  }

  Future<void> reload() async {
    _subscriptions = await repository.listSubscriptions(userId: _userId);
    final subscribedFeedIds = _subscriptions
        .map((subscription) => subscription.feedId)
        .toSet();
    _feeds =
        (await repository.listFeeds())
            .where((feed) => subscribedFeedIds.contains(feed.id))
            .toList(growable: false)
          ..sort(
            (a, b) => titleForFeed(
              a,
            ).toLowerCase().compareTo(titleForFeed(b).toLowerCase()),
          );
    _articles =
        (await repository.listArticles(
              userId: _userId,
              unreadOnly: articleFilter == ArticleFilter.unread,
              starredOnly: articleFilter == ArticleFilter.starred,
              searchQuery: searchQuery,
            ))
            .where((article) => subscribedFeedIds.contains(article.feedId))
            .toList(growable: false);
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
    if (_isImporting) {
      return;
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException(
        'Please provide a valid HTTP(S) RSS or Atom URL.',
      );
    }
    _isImporting = true;
    notifyListeners();
    try {
      final result = await _importer.import(uri);
      final now = DateTime.now().toUtc();
      final existing = subscriptionForFeed(result.feed.id);
      await repository.upsertSubscription(
        Subscription(
          id: existing?.id ?? 'subscription-${result.feed.id}',
          userId: _userId,
          feedId: result.feed.id,
          folderId: existing?.folderId,
          customTitle: existing?.customTitle,
          isMuted: existing?.isMuted ?? false,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
          syncVersion: existing?.syncVersion ?? 0,
        ),
      );
      await reload();
      selectFeed(result.feed.id);
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> refreshSelectedFeed() async {
    final feed = selectedFeed;
    if (feed == null || _isImporting) {
      return;
    }
    await addFeedFromUrl(feed.feedUrl.toString());
  }

  Future<void> renameFeed(String feedId, String? customTitle) async {
    final subscription = subscriptionForFeed(feedId);
    if (subscription == null) {
      return;
    }
    final normalized = customTitle?.trim();
    await repository.upsertSubscription(
      subscription.copyWith(
        customTitle: normalized == null || normalized.isEmpty
            ? null
            : normalized,
        updatedAt: DateTime.now().toUtc(),
        syncVersion: subscription.syncVersion + 1,
      ),
    );
    await reload();
  }

  Future<void> removeFeed(String feedId) async {
    final subscription = subscriptionForFeed(feedId);
    if (subscription == null) {
      return;
    }
    await repository.deleteSubscription(
      subscriptionId: subscription.id,
      deletedAt: DateTime.now().toUtc(),
    );
    await reload();
  }

  Future<void> setArticleFilter(ArticleFilter value) async {
    if (articleFilter == value) {
      return;
    }
    articleFilter = value;
    await reload();
  }

  Future<void> setSearchQuery(String value) async {
    final normalized = value.trim();
    if (searchQuery == normalized) {
      return;
    }
    searchQuery = normalized;
    await reload();
  }

  Future<OpmlImportReport> importOpml(String source) async {
    final document = OpmlDocument.parse(source);
    var imported = 0;
    final failed = <Uri>[];
    for (final entry in document.entries) {
      try {
        await addFeedFromUrl(entry.feedUrl.toString());
        Feed? importedFeed;
        for (final feed in _feeds) {
          if (feed.feedUrl == entry.feedUrl) {
            importedFeed = feed;
            break;
          }
        }
        if (importedFeed != null && entry.title != importedFeed.title) {
          await renameFeed(importedFeed.id, entry.title);
        }
        imported += 1;
      } on Object {
        failed.add(entry.feedUrl);
      }
    }
    return OpmlImportReport(
      imported: imported,
      failedUrls: List<Uri>.unmodifiable(failed),
    );
  }

  String exportOpml() {
    final entries = _feeds
        .map((feed) {
          return OpmlEntry(
            title: titleForFeed(feed),
            feedUrl: feed.feedUrl,
            siteUrl: feed.siteUrl,
          );
        })
        .toList(growable: false);
    return OpmlDocument(entries).encode();
  }

  Future<RetentionPolicy> loadRetentionPolicy() {
    return repository.getRetentionPolicy(_userId);
  }

  Future<int> saveRetentionPolicy(RetentionPolicy policy) async {
    await repository.saveRetentionPolicy(_userId, policy);
    final removed = await repository.cleanUpArticles(
      userId: _userId,
      now: DateTime.now().toUtc(),
    );
    await reload();
    return removed;
  }

  Future<void> markSelectedRead(bool value) async {
    final articleId = selectedArticleId;
    if (articleId == null) {
      return;
    }
    await markArticleRead(articleId, value);
  }

  Future<void> markArticleRead(String articleId, bool value) async {
    final operation = await repository.markArticleRead(
      userId: _userId,
      deviceId: _deviceId,
      clientSequence: await repository.nextClientSequence(_deviceId),
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
    await toggleStar(articleId);
  }

  Future<void> toggleStar(String articleId) async {
    final operation = await repository.toggleArticleStar(
      userId: _userId,
      deviceId: _deviceId,
      clientSequence: await repository.nextClientSequence(_deviceId),
      articleId: articleId,
      isStarred: !isStarred(articleId),
      occurredAt: DateTime.now().toUtc(),
    );

    if (operation != null) {
      await reload();
    }
  }

  /// Selects one feed, or every feed when [feedId] is null.
  void selectFeed(String? feedId) {
    selectedFeedId = feedId;
    final feedArticles = articlesForFeed(feedId);
    selectedArticleId = feedArticles.isEmpty ? null : feedArticles.first.id;
    notifyListeners();
  }

  /// Marks every article currently listed (feed + filter + search) as read.
  /// Returns how many articles changed.
  Future<int> markAllRead() async {
    final targets = articlesForFeed(
      selectedFeedId,
    ).where((article) => !isRead(article.id)).toList(growable: false);
    for (final article in targets) {
      await repository.markArticleRead(
        userId: _userId,
        deviceId: _deviceId,
        clientSequence: await repository.nextClientSequence(_deviceId),
        articleId: article.id,
        isRead: true,
        occurredAt: DateTime.now().toUtc(),
      );
    }
    if (targets.isNotEmpty) {
      await reload();
    }
    return targets.length;
  }

  /// Fills the library with sample content so visitors can try the reader
  /// without an account: a short built-in guide plus the Korben feed
  /// (downloaded live when reachable, bundled teasers otherwise).
  ///
  /// Returns true when the live Korben feed could be downloaded.
  Future<bool> loadDemoContent() async {
    if (_isImporting || _isDemoLoading) {
      return false;
    }
    _isDemoLoading = true;
    notifyListeners();
    var korbenIsLive = true;
    try {
      await _seedWelcomeFeed();
      final korbenUrl = kIsWeb
          ? Uri.base.resolve('demo/korben-feed').toString()
          : 'https://korben.info/feed/';
      try {
        await addFeedFromUrl(korbenUrl);
      } on Object {
        korbenIsLive = false;
        await _seedOfflineKorben();
      }
      await reload();
      selectFeed(null);
      return korbenIsLive;
    } finally {
      _isDemoLoading = false;
      notifyListeners();
    }
  }

  Future<void> _seedWelcomeFeed() async {
    final now = DateTime.now().toUtc();
    const feedId = 'demo-welcome';
    await repository.upsertFeed(
      Feed(
        id: feedId,
        canonicalUrl: Uri.parse('https://github.com/thekester/SynkFeed'),
        feedUrl: Uri.parse('https://github.com/thekester/SynkFeed'),
        siteUrl: Uri.parse('https://github.com/thekester/SynkFeed'),
        title: 'Welcome to SynkFeed',
        description: 'A short tour of the reader.',
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (subscriptionForFeed(feedId) == null) {
      await repository.upsertSubscription(
        Subscription(
          id: 'subscription-$feedId',
          userId: _userId,
          feedId: feedId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await repository.upsertArticles(_welcomeArticles(feedId, now));
  }

  Future<void> _seedOfflineKorben() async {
    final now = DateTime.now().toUtc();
    const feedId = 'demo-korben';
    await repository.upsertFeed(
      Feed(
        id: feedId,
        canonicalUrl: Uri.parse('https://korben.info'),
        feedUrl: Uri.parse('https://korben.info/feed/'),
        siteUrl: Uri.parse('https://korben.info'),
        title: 'Korben',
        description: 'Upgrade your mind - korben.info',
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (subscriptionForFeed(feedId) == null) {
      await repository.upsertSubscription(
        Subscription(
          id: 'subscription-$feedId',
          userId: _userId,
          feedId: feedId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await repository.upsertArticles([
      Article(
        id: 'demo-korben-1',
        feedId: feedId,
        externalId: 'demo-korben-1',
        canonicalUrl: Uri.parse('https://korben.info'),
        title: 'Korben - Upgrade your mind',
        summary:
            'The live feed could not be downloaded right now. Reconnect and '
            'refresh the feed to pull the real articles from korben.info.',
        contentText:
            'korben.info covers tech news, open source, security, and DIY '
            'projects in French. In the full experience this feed is '
            'downloaded automatically with complete articles for offline '
            'reading. Press the refresh button when you are back online.',
        publishedAt: now,
        insertedAt: now,
      ),
    ]);
  }

  List<Article> _welcomeArticles(String feedId, DateTime now) {
    Article article({
      required String slug,
      required String title,
      required String summary,
      required String body,
      required int minutesAgo,
    }) {
      return Article(
        id: 'demo-welcome-$slug',
        feedId: feedId,
        externalId: 'demo-welcome-$slug',
        canonicalUrl: Uri.parse('https://github.com/thekester/SynkFeed'),
        title: title,
        summary: summary,
        contentText: body,
        publishedAt: now.subtract(Duration(minutes: minutesAgo)),
        insertedAt: now,
      );
    }

    return [
      article(
        slug: 'hello',
        title: 'Welcome to SynkFeed 👋',
        summary: 'A fast, offline-first RSS reader you can self-host.',
        body:
            'SynkFeed keeps your articles on your device so you can read '
            'them anywhere, then synchronizes your read and favorite states '
            'across devices through your own server.\n\n'
            'This library is a demo: browse the articles on the left, star '
            'the ones you like, and use the filters at the top. Nothing '
            'leaves your browser until you connect an account.',
        minutesAgo: 2,
      ),
      article(
        slug: 'sync',
        title: 'Bring your own server: FreshRSS or SynkFeed',
        summary: 'One account, every device - reads and favorites follow you.',
        body:
            'Press the cloud button in the top bar to connect this reader to '
            'a FreshRSS instance (Google Reader API) or to a native SynkFeed '
            'server.\n\n'
            'Once connected, your subscriptions are downloaded with full '
            'article content, and everything you read or star here shows up '
            'on your phone, your desktop, and any other RSS client connected '
            'to the same account.',
        minutesAgo: 12,
      ),
      article(
        slug: 'tips',
        title: 'Three tips to get the most out of the reader',
        summary: 'Filters, favorites, and OPML import/export.',
        body:
            '1. The Unread and Favorites filters above the article list keep '
            'long feeds manageable, and the search box matches titles.\n\n'
            '2. The star next to each article saves it as a favorite - '
            'favorites are protected from automatic cleanup.\n\n'
            '3. Coming from another reader? Use the menu to import your '
            'subscriptions as OPML, and export them anytime. Your data '
            'stays yours.',
        minutesAgo: 25,
      ),
    ];
  }

  void selectArticle(String articleId) {
    selectedArticleId = articleId;
    // Opening an article marks it read, like most readers. Skipped while the
    // unread filter is active so the list does not shift under the tap.
    if (articleFilter != ArticleFilter.unread && !isRead(articleId)) {
      unawaited(markArticleRead(articleId, true));
    }
    notifyListeners();
  }

  void _normalizeSelection() {
    if (_feeds.isEmpty) {
      selectedFeedId = null;
      selectedArticleId = null;
      return;
    }

    // A removed feed falls back to the "all articles" view.
    if (selectedFeedId != null &&
        _feeds.every((feed) => feed.id != selectedFeedId)) {
      selectedFeedId = null;
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
