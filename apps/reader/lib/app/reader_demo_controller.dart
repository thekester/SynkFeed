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

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;
    await reload();
    if (selectedFeedId == null && _feeds.isNotEmpty) {
      selectFeed(_feeds.first.id);
    }
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
