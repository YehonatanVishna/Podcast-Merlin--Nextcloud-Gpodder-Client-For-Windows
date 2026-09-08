import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/podcast.dart';
import '../../../core/providers/app_providers.dart';
import '../../sync/opml_service.dart';
import '../widgets/cached_image.dart';
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'OPML & More',
            onSelected: (val) {
              if (val == 'import_opml') {
                _showImportOpmlDialog(context, ref);
              } else if (val == 'export_opml') {
                _exportOpml(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'import_opml',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Import OPML'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export_opml',
                child: Row(
                  children: [
                    Icon(Icons.file_upload_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Export OPML'),
                  ],
                ),
              ),
            ],
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
          ] else if (syncStatus.hasFeedWarnings) ...[
            SyncErrorBanner(
              errorMessage: 'Sync completed, but dead/failing podcast feed(s) were detected:\n${syncStatus.feedWarnings.join('\n')}',
              onDismiss: () => ref.read(syncStatusNotifierProvider.notifier).clearWarnings(),
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

  Future<void> _exportOpml(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final podcasts = await db.getAllPodcasts();
    final xmlContent = OpmlService.generateOpml(podcasts: podcasts);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export Subscriptions (${podcasts.length} feeds)'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('OPML 2.0 XML:'),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: xmlContent),
                maxLines: 10,
                readOnly: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy to Clipboard'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: xmlContent));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exported ${podcasts.length} subscriptions to OPML (copied to clipboard)')),
              );
            },
          ),
        ],
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${podcasts.length} subscriptions to OPML')),
    );
  }

  void _showImportOpmlDialog(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();
    bool syncWithServer = true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final outlines = OpmlService.parseOpml(textController.text);

          return AlertDialog(
            title: const Text('Import Subscriptions from OPML'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Paste OPML 2.0 XML or file content below:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '<opml version="2.0">...',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: outlines.isNotEmpty
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      outlines.isNotEmpty
                          ? 'Detected ${outlines.length} podcast(s):\n${outlines.take(4).map((o) => '• ${o.title.isNotEmpty ? o.title : o.xmlUrl}').join('\n')}${outlines.length > 4 ? '\n• ...and ${outlines.length - 4} more' : ''}'
                          : 'Paste valid OPML XML above to preview feeds',
                      style: TextStyle(
                        fontSize: 12,
                        color: outlines.isNotEmpty ? Colors.green[900] : Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Sync new feeds with gPodder', style: TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: syncWithServer,
                    onChanged: (val) => setDialogState(() => syncWithServer = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: outlines.isEmpty
                    ? null
                    : () async {
                        final db = ref.read(databaseProvider);
                        final imported = await OpmlService.importOpml(
                          textController.text,
                          db,
                          syncWithServer: syncWithServer,
                        );
                        await ref.read(podcastsNotifierProvider.notifier).loadPodcasts();
                        if (syncWithServer) {
                          ref.read(syncStatusNotifierProvider.notifier).pushBacklog().catchError((_) => false);
                        }
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Successfully imported ${imported.length} new podcast(s)')),
                          );
                        }
                      },
                child: Text('Import (${outlines.length})'),
              ),
            ],
          );
        },
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
                  AppCachedImage(
                    imageUrl: podcast.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: SvgPicture.asset(
                      'assets/images/logo.svg',
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (podcast.isDead)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Dead Feed',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    podcast.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (podcast.isDead && podcast.lastFeedError != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      podcast.lastFeedError!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: Colors.red[700], fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
