import 'package:flutter/material.dart';

import '../../app/reader_demo_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final ReaderDemoController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1080;
            final body = isWide
                ? _DesktopLayout(controller: controller)
                : _MobileLayout(controller: controller);
            final actions = isWide
                ? <Widget>[
                    IconButton(
                      tooltip: 'Reload demo content',
                      onPressed: controller.reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _showAddFeedDialog(context, controller),
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Add feed'),
                    ),
                    const SizedBox(width: 12),
                  ]
                : <Widget>[
                    IconButton(
                      tooltip: 'Reload demo content',
                      onPressed: controller.reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: 'Add feed',
                      onPressed: () => _showAddFeedDialog(context, controller),
                      icon: const Icon(Icons.add_link_rounded),
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
                          ? 'Local data first, sync later'
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
      return const Center(child: Text('No feeds yet.'));
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
                        feed.title,
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
    if (articles.isEmpty) {
      return const Center(child: Text('No articles available.'));
    }

    return ListView.separated(
      itemCount: articles.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
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
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
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
            article.summary ?? article.contentText ?? 'No summary available.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: state?.isRead == true
              ? const Icon(Icons.done_rounded)
              : null,
        );
      },
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
              } on FormatException catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
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
