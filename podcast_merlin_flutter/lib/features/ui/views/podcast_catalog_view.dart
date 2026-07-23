import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/podcast.dart';
import '../../../core/providers/app_providers.dart';

class PodcastCatalogView extends ConsumerWidget {
  final ValueChanged<Podcast>? onPodcastSelected;

  const PodcastCatalogView({super.key, this.onPodcastSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podcastsState = ref.watch(podcastsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 32,
              height: 32,
              cacheWidth: 64,
              cacheHeight: 64,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.podcasts, size: 32),
            ),
            const SizedBox(width: 12),
            const Text('Podcast Merlin'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync & Refresh All',
            onPressed: () {
              ref.read(podcastsNotifierProvider.notifier).refreshAll();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Subscribe to RSS Feed',
            onPressed: () => _showAddPodcastDialog(context, ref),
          ),
        ],
      ),
      body: podcastsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Error loading catalog: $err'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(podcastsNotifierProvider.notifier).loadPodcasts(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (podcasts) {
          if (podcasts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.podcasts, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No Podcast Subscriptions Yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Click + to add an RSS feed or sync with Nextcloud'),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add RSS Feed'),
                    onPressed: () => _showAddPodcastDialog(context, ref),
                  ),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 900
                  ? 5
                  : (constraints.maxWidth > 600 ? 3 : 2);

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: podcasts.length,
                itemBuilder: (context, index) {
                  final pod = podcasts[index];
                  return _PodcastCard(
                    podcast: pod,
                    onTap: () => onPodcastSelected?.call(pod),
                    onDelete: () {
                      ref.read(podcastsNotifierProvider.notifier).removePodcast(pod.rssUrl);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showAddPodcastDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Subscribe to Podcast Feed'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/podcast.xml',
            labelText: 'RSS Feed URL',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Downloading & parsing RSS feed...')),
                );
                final success = await ref
                    .read(podcastsNotifierProvider.notifier)
                    .addPodcastFeed(url);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success ? 'Subscribed successfully!' : 'Failed to parse RSS feed',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );
  }
}

class _PodcastCard extends StatelessWidget {
  final Podcast podcast;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PodcastCard({
    required this.podcast,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  podcast.imageUrl.isNotEmpty
                      ? Image.network(
                          podcast.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Image.asset(
                            'assets/images/logo_square.png',
                            fit: BoxFit.cover,
                          ),
                        )
                      : Image.asset(
                          'assets/images/logo_square.png',
                          fit: BoxFit.cover,
                        ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (val) {
                        if (val == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Unsubscribe'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                podcast.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
