import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/podcast.dart';
import '../../../core/providers/app_providers.dart';
import '../widgets/sync_error_banner.dart';

class PodcastCatalogView extends ConsumerWidget {
  final ValueChanged<Podcast>? onPodcastSelected;

  const PodcastCatalogView({super.key, this.onPodcastSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podcastsState = ref.watch(podcastsNotifierProvider);
    final syncStatus = ref.watch(syncStatusNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/images/logo.svg',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 12),
            const Text('Podcast Merlin'),
          ],
        ),
        actions: [
          IconButton(
            icon: syncStatus.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.refresh),
            tooltip: syncStatus.isSyncing ? (syncStatus.currentTask ?? 'Syncing...') : 'Sync & Refresh All',
            onPressed: syncStatus.isSyncing
                ? null
                : () {
                    ref.read(podcastsNotifierProvider.notifier).refreshAll();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Subscribe to RSS Feed',
            onPressed: syncStatus.isSyncing ? null : () => _showAddPodcastDialog(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          if (syncStatus.isSyncing) ...[
            const LinearProgressIndicator(minHeight: 3),
            Container(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      syncStatus.currentTask ?? 'Processing...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (syncStatus.error != null) ...[
            SyncErrorBanner(
              errorMessage: syncStatus.error!,
              onDismiss: () => ref.read(syncStatusNotifierProvider.notifier).clearError(),
              onRetry: () => ref.read(podcastsNotifierProvider.notifier).refreshAll(),
            ),
          ],
          Expanded(
            child: podcastsState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        'Error loading catalog: $err',
                        textAlign: TextAlign.center,
                      ),
                    ),
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
          ),
        ],
      ),
    );
  }

  void _showAddPodcastDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Consumer(
          builder: (context, ref, child) {
            final syncState = ref.watch(syncStatusNotifierProvider);
            final isSubscribing = syncState.isSyncing;

            return AlertDialog(
              title: const Text('Subscribe to Podcast Feed'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    enabled: !isSubscribing,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/podcast.xml',
                      labelText: 'RSS Feed URL',
                    ),
                    autofocus: true,
                  ),
                  if (isSubscribing) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            syncState.currentTask ?? 'Downloading & parsing RSS feed...',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubscribing ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubscribing
                      ? null
                      : () async {
                          final url = controller.text.trim();
                          if (url.isNotEmpty) {
                            final success = await ref
                                .read(podcastsNotifierProvider.notifier)
                                .addPodcastFeed(url);

                            final latestError = ref.read(syncStatusNotifierProvider).error;

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: success ? Colors.green[700] : Colors.red[700],
                                  content: Text(
                                    success
                                        ? 'Subscribed successfully!'
                                        : (latestError ?? 'Failed to parse RSS feed'),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: isSubscribing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Subscribe'),
                ),
              ],
            );
          },
        );
      },
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
                          errorBuilder: (context, error, stackTrace) => SvgPicture.asset(
                            'assets/images/logo.svg',
                            fit: BoxFit.cover,
                          ),
                        )
                      : SvgPicture.asset(
                          'assets/images/logo.svg',
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
