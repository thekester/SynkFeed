import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
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
                ? _DesktopLayout(controller: controller)
                : _MobileLayout(controller: controller);
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

            return Scaffold(
              appBar: AppBar(
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SynkFeed'),
                    Text(
                      controller.pendingOperationCount == 0
                          ? controller.isImporting
                                ? 'Downloading feed for offline reading...'
                                : 'Local data first, sync later'
                          : '${controller.pendingOperationCount} action(s) waiting to sync',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                actions: actions,
              ),
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF7F4ED), Color(0xFFF1F5F9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(child: body),
              ),
            );
          },
        );
      },
    );
  }
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
    return IconButton(
      tooltip: 'Sync now',
      onPressed: () => _syncNow(context, controller, syncController),
      icon: const Icon(Icons.cloud_sync_rounded),
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
  const _DesktopLayout({required this.controller});

  final ReaderDemoController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: _PanelCard(
              title: 'Feeds',
              child: _FeedList(controller: controller),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: _PanelCard(
              title: 'Articles',
              child: _ArticleList(controller: controller),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: _PanelCard(
              title: 'Reader',
              child: _ArticleReader(controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.controller});

  final ReaderDemoController controller;

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
                _FeedList(controller: controller),
                _ArticleList(controller: controller),
                _ArticleReader(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const _FeedList({required this.controller});

  final ReaderDemoController controller;

  @override
  Widget build(BuildContext context) {
    final feeds = controller.feeds;
    if (feeds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No feeds yet. Add an RSS or Atom URL to build your offline library.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: feeds.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final feed = feeds[index];
        final selected = feed.id == controller.selectedFeedId;
        final articleCount = controller.articlesForFeed(feed.id).length;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => controller.selectFeed(feed.id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.rss_feed_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.titleForFeed(feed),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feed.feedUrl.host.isEmpty
                            ? feed.feedUrl.toString()
                            : feed.feedUrl.host,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Chip(label: Text('$articleCount')),
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
        Wrap(
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
        const SizedBox(height: 8),
        Expanded(
          child: articles.isEmpty
              ? const Center(child: Text('No matching articles.'))
              : ListView.separated(
                  itemCount: articles.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final article = articles[index];
                    final state = controller.stateFor(article.id);
                    final selected = article.id == controller.selectedArticleId;

                    return ListTile(
                      selected: selected,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      tileColor: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                      onTap: () => controller.selectArticle(article.id),
                      leading: Icon(
                        state?.isStarred == true
                            ? Icons.star_rounded
                            : state?.isRead == true
                            ? Icons.mark_email_read_rounded
                            : Icons.article_rounded,
                      ),
                      title: Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        article.summary ??
                            article.contentText ??
                            'No summary available.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: state?.isRead == true
                          ? const Icon(Icons.done_rounded)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ArticleReader extends StatelessWidget {
  const _ArticleReader({required this.controller});

  final ReaderDemoController controller;

  @override
  Widget build(BuildContext context) {
    final article = controller.selectedArticle;
    if (article == null) {
      return const Center(child: Text('Select an article to read it offline.'));
    }

    final state = controller.stateFor(article.id);

    return ListView(
      padding: const EdgeInsets.only(right: 4),
      children: [
        Text(article.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(state?.isRead == true ? 'Read' : 'Unread')),
            Chip(
              label: Text(
                state?.isStarred == true ? 'Favorite' : 'Not favorite',
              ),
            ),
            if (article.publishedAt != null)
              Chip(label: Text('${article.publishedAt!.toLocal()}')),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          article.summary ??
              article.contentText ??
              'No offline content captured yet.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        if (article.contentHtml != null)
          Text(
            article.contentText ?? article.contentHtml!,
            style: Theme.of(context).textTheme.bodyMedium,
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
              label: Text(state?.isRead == true ? 'Mark unread' : 'Mark read'),
            ),
            FilledButton.icon(
              onPressed: controller.toggleSelectedStar,
              icon: Icon(
                state?.isStarred == true
                    ? Icons.star_border_rounded
                    : Icons.star_rounded,
              ),
              label: Text(state?.isStarred == true ? 'Unfavorite' : 'Favorite'),
            ),
          ],
        ),
      ],
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

  Future<void> submit(BuildContext dialogContext, bool createAccount) async {
    try {
      await syncController.signIn(
        serverUrl: serverController.text,
        email: emailController.text,
        password: passwordController.text,
        createAccount: createAccount,
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
    builder: (dialogContext) => AnimatedBuilder(
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
                    subtitle: Text(session.serverUrl.toString()),
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
        return AlertDialog(
          title: const Text('Connect to a sync server'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: serverController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://synkfeed.example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 12 characters',
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
