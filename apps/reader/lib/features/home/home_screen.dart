import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synkfeed_core/synkfeed_core.dart';

import '../../app/reader_demo_controller.dart';
import '../../app/sync_account_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.syncController,
  });

  final ReaderDemoController controller;
  final SyncAccountController syncController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, syncController]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1080;
            final body = isWide
                ? _DesktopLayout(
                    controller: controller,
                    syncController: syncController,
                  )
                : _MobileLayout(
                    controller: controller,
                    syncController: syncController,
                  );
            final syncButton = _SyncButton(
              controller: controller,
              syncController: syncController,
            );
            final actions = isWide
                ? <Widget>[
                    IconButton(
                      tooltip: 'Refresh selected feed',
                      onPressed: controller.isImporting
                          ? null
                          : () => _refreshSelectedFeed(context, controller),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    syncButton,
                    FilledButton.tonalIcon(
                      onPressed: controller.isImporting
                          ? null
                          : () => _showAddFeedDialog(context, controller),
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Add feed'),
                    ),
                    _LibraryMenu(
                      controller: controller,
                      syncController: syncController,
                    ),
                    const SizedBox(width: 12),
                  ]
                : <Widget>[
                    IconButton(
                      tooltip: 'Refresh selected feed',
                      onPressed: controller.isImporting
                          ? null
                          : () => _refreshSelectedFeed(context, controller),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    syncButton,
                    IconButton(
                      tooltip: 'Add feed',
                      onPressed: controller.isImporting
                          ? null
                          : () => _showAddFeedDialog(context, controller),
                      icon: const Icon(Icons.add_link_rounded),
                    ),
                    _LibraryMenu(
                      controller: controller,
                      syncController: syncController,
                    ),
                    const SizedBox(width: 8),
                  ];

            final colorScheme = Theme.of(context).colorScheme;
            final busy =
                controller.isImporting ||
                controller.isDemoLoading ||
                syncController.isBusy;
            return Scaffold(
              backgroundColor: colorScheme.surfaceContainerLowest,
              appBar: AppBar(
                backgroundColor: colorScheme.surfaceContainerLowest,
                scrolledUnderElevation: 0,
                titleSpacing: 16,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colorScheme.primary, colorScheme.tertiary],
                        ),
                      ),
                      child: Icon(
                        Icons.rss_feed_rounded,
                        size: 20,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SynkFeed',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _statusLine(controller, syncController),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: actions,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: busy
                      ? const LinearProgressIndicator(minHeight: 2)
                      : const SizedBox(height: 2),
                ),
              ),
              body: SafeArea(child: body),
            );
          },
        );
      },
    );
  }
}

String _statusLine(
  ReaderDemoController controller,
  SyncAccountController syncController,
) {
  if (controller.isImporting) {
    return 'Downloading feed for offline reading...';
  }
  if (controller.pendingOperationCount > 0) {
    return '${controller.pendingOperationCount} change(s) waiting to sync';
  }
  final session = syncController.session;
  if (session != null) {
    final backend = session.backend == SyncBackend.greader
        ? 'FreshRSS'
        : 'SynkFeed server';
    return '$backend - ${session.email ?? session.serverUrl.host}';
  }
  return 'Local library - connect a server to sync';
}

String _relativeTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  final difference = DateTime.now().toUtc().difference(value.toUtc());
  if (difference.inMinutes < 1) {
    return 'now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} min';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours} h';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays} d';
  }
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class _LibraryMenu extends StatelessWidget {
  const _LibraryMenu({required this.controller, required this.syncController});

  final ReaderDemoController controller;
  final SyncAccountController syncController;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Library actions',
      onSelected: (action) {
        if (action == 'import') {
          _importOpml(context, controller);
        } else if (action == 'export') {
          _exportOpml(context, controller);
        } else if (action == 'storage') {
          _showRetentionSettings(context, controller);
        } else if (action == 'account') {
          _showAccountDialog(context, controller, syncController);
        }
      },
      itemBuilder: (context) => const <PopupMenuEntry<String>>[
        PopupMenuItem(value: 'import', child: Text('Import OPML')),
        PopupMenuItem(value: 'export', child: Text('Export OPML')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'storage', child: Text('Offline storage')),
        PopupMenuItem(value: 'account', child: Text('Account & sync')),
      ],
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.controller, required this.syncController});

  final ReaderDemoController controller;
  final SyncAccountController syncController;

  @override
  Widget build(BuildContext context) {
    if (syncController.isBusy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!syncController.isSignedIn) {
      return IconButton(
        tooltip: 'Connect to a sync server',
        onPressed: () =>
            _showAccountDialog(context, controller, syncController),
        icon: const Icon(Icons.cloud_off_rounded),
      );
    }
    final pending = controller.pendingOperationCount;
    return IconButton(
      tooltip: 'Sync now',
      onPressed: () => _syncNow(context, controller, syncController),
      icon: pending == 0
          ? const Icon(Icons.cloud_sync_rounded)
          : Badge.count(
              count: pending,
              child: const Icon(Icons.cloud_sync_rounded),
            ),
    );
  }
}

Future<void> _loadDemo(
  BuildContext context,
  ReaderDemoController controller,
) async {
  final korbenIsLive = await controller.loadDemoContent();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          korbenIsLive
              ? 'Demo library ready - including the live Korben feed.'
              : 'Demo library ready (offline sample - refresh Korben once online).',
        ),
      ),
    );
  }
}

Future<void> _syncNow(
  BuildContext context,
  ReaderDemoController controller,
  SyncAccountController syncController,
) async {
  try {
    final report = await syncController.syncNow();
    await controller.reload();
    if (context.mounted && report != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync done: ${report.pushedOperations} sent, '
            '${report.appliedChanges} received'
            '${report.rejectedOperations == 0 ? '' : ', ${report.rejectedOperations} rejected'}.',
          ),
        ),
      );
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SyncAccountController.describeError(error))),
      );
    }
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.controller,
    required this.syncController,
  });

  final ReaderDemoController controller;
  final SyncAccountController syncController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          SizedBox(
            width: 300,
            child: _PanelCard(
              title: 'Feeds',
              icon: Icons.rss_feed_rounded,
              trailing: controller.totalUnreadCount == 0
                  ? null
                  : '${controller.totalUnreadCount} unread',
              child: _FeedList(
                controller: controller,
                syncController: syncController,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _PanelCard(
              title: 'Articles',
              icon: Icons.article_outlined,
              child: _ArticleList(controller: controller),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: _PanelCard(
              title: 'Reader',
              icon: Icons.chrome_reader_mode_outlined,
              child: _ArticleReader(controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.controller, required this.syncController});

  final ReaderDemoController controller;
  final SyncAccountController syncController;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Feeds'),
              Tab(text: 'Articles'),
              Tab(text: 'Reader'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _FeedList(
                    controller: controller,
                    syncController: syncController,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ArticleList(controller: controller),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ArticleReader(controller: controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const _FeedList({required this.controller, required this.syncController});

  final ReaderDemoController controller;
  final SyncAccountController syncController;

  @override
  Widget build(BuildContext context) {
    final feeds = controller.feeds;
    final colorScheme = Theme.of(context).colorScheme;
    if (feeds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.rss_feed_rounded,
                size: 56,
                color: colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Your library is empty',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                syncController.isSignedIn
                    ? 'Press "Sync now" to download your subscriptions, or add a feed URL.'
                    : 'Try the demo library, connect to your server, or add any RSS/Atom URL.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (syncController.isSignedIn)
                FilledButton.icon(
                  onPressed: () =>
                      _syncNow(context, controller, syncController),
                  icon: const Icon(Icons.cloud_sync_rounded),
                  label: const Text('Sync now'),
                )
              else ...[
                FilledButton.icon(
                  onPressed: controller.isDemoLoading
                      ? null
                      : () => _loadDemo(context, controller),
                  icon: controller.isDemoLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    controller.isDemoLoading
                        ? 'Preparing the demo...'
                        : 'Try the demo',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      _showAccountDialog(context, controller, syncController),
                  icon: const Icon(Icons.cloud_rounded),
                  label: const Text('Connect to a server'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _showAddFeedDialog(context, controller),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Add a feed URL'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: feeds.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _AllArticlesTile(controller: controller);
        }
        final feed = feeds[index - 1];
        final selected = feed.id == controller.selectedFeedId;
        final unread = controller.unreadCountForFeed(feed.id);

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => controller.selectFeed(feed.id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? colorScheme.secondaryContainer : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: selected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.rss_feed_rounded,
                    size: 16,
                    color: selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.titleForFeed(feed),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: unread > 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      Text(
                        feed.feedUrl.host.isEmpty
                            ? feed.feedUrl.toString()
                            : feed.feedUrl.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unread',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Feed actions',
                  onSelected: (action) async {
                    if (action == 'rename') {
                      await _showRenameFeedDialog(context, controller, feed);
                    } else if (action == 'remove') {
                      await _confirmRemoveFeed(context, controller, feed);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Rename'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Remove'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArticleList extends StatelessWidget {
  const _ArticleList({required this.controller});

  final ReaderDemoController controller;

  @override
  Widget build(BuildContext context) {
    final articles = controller.articlesForFeed(controller.selectedFeedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: ValueKey(controller.searchQuery),
          initialValue: controller.searchQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search article titles',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => controller.setSearchQuery(''),
                    icon: const Icon(Icons.close_rounded),
                  ),
            border: const OutlineInputBorder(),
          ),
          onFieldSubmitted: controller.setSearchQuery,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                children: ArticleFilter.values
                    .map((filter) {
                      return ChoiceChip(
                        label: Text(switch (filter) {
                          ArticleFilter.all => 'All',
                          ArticleFilter.unread => 'Unread',
                          ArticleFilter.starred => 'Favorites',
                        }),
                        selected: controller.articleFilter == filter,
                        onSelected: (_) => controller.setArticleFilter(filter),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: articles.isEmpty
                  ? null
                  : () async {
                      final changed = await controller.markAllRead();
                      if (context.mounted && changed > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$changed article(s) marked read.'),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.done_all_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_rounded,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      const Text('No matching articles.'),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: articles.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final article = articles[index];
                    return _ArticleTile(
                      controller: controller,
                      article: article,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AllArticlesTile extends StatelessWidget {
  const _AllArticlesTile({required this.controller});

  final ReaderDemoController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = controller.selectedFeedId == null;
    final unread = controller.totalUnreadCount;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => controller.selectFeed(null),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? colorScheme.secondaryContainer : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: selected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.all_inbox_rounded,
                size: 16,
                color: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'All articles',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$unread',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({required this.controller, required this.article});

  final ReaderDemoController controller;
  final Article article;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRead = controller.isRead(article.id);
    final isStarred = controller.isStarred(article.id);
    final selected = article.id == controller.selectedArticleId;
    final feedTitle = controller.feedTitleById(article.feedId);
    final time = _relativeTime(article.publishedAt);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => controller.selectArticle(article.id),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? colorScheme.secondaryContainer : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRead ? Colors.transparent : colorScheme.primary,
                  border: isRead
                      ? Border.all(color: colorScheme.outlineVariant)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                      color: isRead ? colorScheme.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (feedTitle.isNotEmpty) feedTitle,
                      if (time.isNotEmpty) time,
                    ].join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isStarred ? 'Remove favorite' : 'Add to favorites',
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.toggleStar(article.id),
              icon: Icon(
                isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
                color: isStarred ? Colors.amber : colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleReader extends StatelessWidget {
  const _ArticleReader({required this.controller});

  final ReaderDemoController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final article = controller.selectedArticle;
    if (article == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chrome_reader_mode_outlined,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text('Select an article to read it offline.'),
          ],
        ),
      );
    }

    final state = controller.stateFor(article.id);
    final feedTitle = controller.feedTitleById(article.feedId);
    final published = article.publishedAt?.toLocal();
    final meta = <String>[
      if (feedTitle.isNotEmpty) feedTitle,
      if (article.author != null && article.author!.trim().isNotEmpty)
        article.author!.trim(),
      if (published != null)
        '${published.year}-${published.month.toString().padLeft(2, '0')}-${published.day.toString().padLeft(2, '0')} '
            '${published.hour.toString().padLeft(2, '0')}:${published.minute.toString().padLeft(2, '0')}',
    ].join('  -  ');

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.only(right: 4),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    article.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: state?.isStarred == true
                      ? 'Remove favorite'
                      : 'Add to favorites',
                  onPressed: controller.toggleSelectedStar,
                  icon: Icon(
                    state?.isStarred == true
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: state?.isStarred == true
                        ? Colors.amber
                        : colorScheme.outline,
                  ),
                ),
              ],
            ),
            if (meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  meta,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              article.contentText ??
                  article.summary ??
                  'No offline content captured yet.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      controller.markSelectedRead(!(state?.isRead ?? false)),
                  icon: Icon(
                    state?.isRead == true
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  label: Text(
                    state?.isRead == true ? 'Mark unread' : 'Mark read',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: article.canonicalUrl.toString()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Article link copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Copy link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddFeedDialog(
  BuildContext context,
  ReaderDemoController controller,
) async {
  final inputController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Add RSS feed'),
        content: TextField(
          controller: inputController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Feed URL',
            hintText: 'https://example.com/feed.xml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await controller.addFeedFromUrl(inputController.text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } on Object catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      );
    },
  );

  inputController.dispose();
}

String _errorMessage(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  return 'Unable to download this feed. Check the URL and your connection.';
}

Future<void> _refreshSelectedFeed(
  BuildContext context,
  ReaderDemoController controller,
) async {
  try {
    await controller.refreshSelectedFeed();
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
    }
  }
}

Future<void> _showRenameFeedDialog(
  BuildContext context,
  ReaderDemoController controller,
  Feed feed,
) async {
  final input = TextEditingController(text: controller.titleForFeed(feed));
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Rename feed'),
      content: TextField(
        controller: input,
        autofocus: true,
        decoration: InputDecoration(hintText: feed.title),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(input.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  input.dispose();
  if (value != null) {
    await controller.renameFeed(feed.id, value == feed.title ? null : value);
  }
}

Future<void> _confirmRemoveFeed(
  BuildContext context,
  ReaderDemoController controller,
  Feed feed,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove feed?'),
      content: Text(
        '${controller.titleForFeed(feed)} will be removed from this library. '
        'Already downloaded data stays available for synchronization recovery.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.removeFeed(feed.id);
  }
}

Future<void> _importOpml(
  BuildContext context,
  ReaderDemoController controller,
) async {
  try {
    const typeGroup = XTypeGroup(
      label: 'OPML subscriptions',
      extensions: <String>['opml', 'xml'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (file == null) {
      return;
    }
    final report = await controller.importOpml(await file.readAsString());
    if (context.mounted) {
      final failed = report.failedUrls.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? '${report.imported} feed(s) imported.'
                : '${report.imported} imported, $failed failed.',
          ),
        ),
      );
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
    }
  }
}

Future<void> _exportOpml(
  BuildContext context,
  ReaderDemoController controller,
) async {
  try {
    const typeGroup = XTypeGroup(
      label: 'OPML subscriptions',
      extensions: <String>['opml'],
    );
    final location = await getSaveLocation(
      suggestedName: 'synkfeed-subscriptions.opml',
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (location == null) {
      return;
    }
    final data = utf8.encode(controller.exportOpml());
    final file = XFile.fromData(
      data,
      mimeType: 'text/x-opml',
      name: 'synkfeed-subscriptions.opml',
    );
    await file.saveTo(location.path);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('OPML export saved.')));
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
    }
  }
}

Future<void> _showAccountDialog(
  BuildContext context,
  ReaderDemoController controller,
  SyncAccountController syncController,
) async {
  final serverController = TextEditingController(
    text:
        syncController.session?.serverUrl.toString() ?? 'http://localhost:3000',
  );
  final emailController = TextEditingController(
    text: syncController.session?.email ?? '',
  );
  final passwordController = TextEditingController();
  var backend = syncController.session?.backend ?? SyncBackend.synkfeed;

  Future<void> submit(BuildContext dialogContext, bool createAccount) async {
    try {
      await syncController.signIn(
        serverUrl: serverController.text,
        email: emailController.text,
        password: passwordController.text,
        createAccount: createAccount,
        backend: backend,
      );
      passwordController.clear();
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected. Your reading state can now sync.'),
          ),
        );
      }
    } on Object catch (error) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(SyncAccountController.describeError(error))),
        );
      }
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AnimatedBuilder(
        animation: syncController,
        builder: (context, _) {
          final session = syncController.session;
          final busy = syncController.isBusy;
          if (session != null) {
            final report = syncController.lastReport;
            final syncedAt = syncController.lastSyncAt;
            return AlertDialog(
              title: const Text('Account & sync'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_done_rounded),
                      title: Text(session.email ?? 'Signed in'),
                      subtitle: Text(
                        '${session.backend == SyncBackend.greader ? 'FreshRSS - ' : ''}'
                        '${session.serverUrl}',
                      ),
                    ),
                    if (report != null && syncedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Last sync ${syncedAt.toLocal()}: '
                          '${report.pushedOperations} sent, '
                          '${report.appliedChanges} received'
                          '${report.rejectedOperations == 0 ? '' : ', ${report.rejectedOperations} rejected'}.',
                        ),
                      ),
                    if (syncController.lastError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          syncController.lastError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : syncController.signOut,
                  child: const Text('Sign out'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _syncNow(context, controller, syncController),
                  icon: const Icon(Icons.cloud_sync_rounded),
                  label: const Text('Sync now'),
                ),
              ],
            );
          }
          final isGReader = backend == SyncBackend.greader;
          return AlertDialog(
            title: const Text('Connect to a sync server'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<SyncBackend>(
                    segments: const [
                      ButtonSegment(
                        value: SyncBackend.synkfeed,
                        label: Text('SynkFeed'),
                        icon: Icon(Icons.dns_rounded),
                      ),
                      ButtonSegment(
                        value: SyncBackend.greader,
                        label: Text('FreshRSS'),
                        icon: Icon(Icons.rss_feed_rounded),
                      ),
                    ],
                    selected: {backend},
                    onSelectionChanged: (selection) =>
                        setState(() => backend = selection.single),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: serverController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Server URL',
                      hintText: isGReader
                          ? 'https://rss.example.com'
                          : 'https://synkfeed.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: isGReader ? 'Username or email' : 'Email',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: isGReader ? 'API password' : 'Password',
                      helperText: isGReader
                          ? 'FreshRSS: Settings > Profile > API management'
                          : 'At least 12 characters',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              if (!isGReader)
                OutlinedButton(
                  onPressed: busy ? null : () => submit(dialogContext, true),
                  child: const Text('Create account'),
                ),
              FilledButton(
                onPressed: busy ? null : () => submit(dialogContext, false),
                child: const Text('Sign in'),
              ),
            ],
          );
        },
      ),
    ),
  );

  serverController.dispose();
  emailController.dispose();
  passwordController.dispose();
}

Future<void> _showRetentionSettings(
  BuildContext context,
  ReaderDemoController controller,
) async {
  final policy = await controller.loadRetentionPolicy();
  if (!context.mounted) {
    return;
  }
  var retentionDays = policy.retentionDays ?? 0;
  var preserveUnread = policy.preserveUnread;
  var preserveStarred = policy.preserveStarred;
  var downloadImages = policy.downloadImages;
  var imagesOnWifiOnly = policy.imagesOnWifiOnly;
  final maximumController = TextEditingController(
    text: policy.maximumArticlesPerFeed?.toString() ?? '',
  );

  final updated = await showDialog<RetentionPolicy>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Offline storage'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: retentionDays,
                  decoration: const InputDecoration(
                    labelText: 'Keep downloaded articles',
                  ),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                    DropdownMenuItem(value: 90, child: Text('90 days')),
                    DropdownMenuItem(value: 0, child: Text('Unlimited')),
                  ],
                  onChanged: (value) =>
                      setState(() => retentionDays = value ?? 30),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maximumController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum articles per feed',
                    hintText: 'No limit',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Always preserve unread articles'),
                  value: preserveUnread,
                  onChanged: (value) => setState(() => preserveUnread = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Always preserve favorites'),
                  value: preserveStarred,
                  onChanged: (value) => setState(() => preserveStarred = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Download images'),
                  value: downloadImages,
                  onChanged: (value) => setState(() {
                    downloadImages = value;
                    if (!value) {
                      imagesOnWifiOnly = false;
                    }
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Images on Wi-Fi only'),
                  value: imagesOnWifiOnly,
                  onChanged: downloadImages
                      ? (value) => setState(() => imagesOnWifiOnly = value)
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final maximum = int.tryParse(maximumController.text.trim());
              if (maximumController.text.trim().isNotEmpty &&
                  (maximum == null || maximum <= 0)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'The article limit must be a positive number.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(
                policy.copyWith(
                  retentionDays: retentionDays == 0 ? null : retentionDays,
                  maximumArticlesPerFeed: maximum,
                  preserveUnread: preserveUnread,
                  preserveStarred: preserveStarred,
                  downloadImages: downloadImages,
                  imagesOnWifiOnly: imagesOnWifiOnly,
                ),
              );
            },
            child: const Text('Save and clean up'),
          ),
        ],
      ),
    ),
  );
  maximumController.dispose();
  if (updated == null) {
    return;
  }
  final removed = await controller.saveRetentionPolicy(updated);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$removed article(s) removed from local storage.'),
      ),
    );
  }
}
