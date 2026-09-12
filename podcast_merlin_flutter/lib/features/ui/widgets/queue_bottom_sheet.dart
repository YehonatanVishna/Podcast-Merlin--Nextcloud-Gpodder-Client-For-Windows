import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';
import 'cached_image.dart';

class QueueBottomSheet extends ConsumerWidget {
  const QueueBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const QueueBottomSheet(),
    );
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioHandler = ref.watch(audioHandlerProvider);
    final currentEpisode = audioHandler.currentEpisode;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<List<Episode>>(
          stream: audioHandler.queueStream,
          initialData: audioHandler.currentQueue,
          builder: (context, snapshot) {
            final queue = snapshot.data ?? audioHandler.currentQueue;

            return SafeArea(
              top: false,
              child: Column(
                children: [
                  // Top drag handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.queue_music, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Up Next Queue',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (queue.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear Queue'),
                            onPressed: () {
                              audioHandler.clearQueue();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Sheet Body
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 20),
                      children: [
                        // Now Playing Section
                      if (currentEpisode != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Text(
                            'NOW PLAYING',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: ListTile(
                            leading: AppCachedImage(
                              imageUrl: currentEpisode.imageUrl,
                              width: 48,
                              height: 48,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            title: Text(
                              currentEpisode.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              _formatDuration(currentEpisode.duration),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: Icon(
                              Icons.volume_up,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Up Next Section Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text(
                          'UP NEXT (${queue.length})',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                        ),
                      ),
                      // Queue List or Empty State
                      if (queue.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.queue_music_outlined,
                                  size: 48,
                                  color: Theme.of(context).disabledColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Queue is empty',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Add episodes to queue using "Play Next" or "Add to Queue".',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).disabledColor,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: queue.length,
                          onReorderItem: (oldIndex, newIndex) {
                            audioHandler.reorderQueue(oldIndex, newIndex);
                          },
                          itemBuilder: (context, index) {
                            final ep = queue[index];
                            final key = ValueKey('queue_item_${ep.id ?? ep.mediaUrl}_$index');

                            return Dismissible(
                              key: key,
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red.shade700,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (_) {
                                if (ep.id != null) {
                                  audioHandler.removeFromQueue(ep.id!);
                                }
                              },
                              child: ListTile(
                                leading: AppCachedImage(
                                  imageUrl: ep.imageUrl,
                                  width: 48,
                                  height: 48,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                title: Text(
                                  ep.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: ep.duration > 0
                                    ? Text(_formatDuration(ep.duration))
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      tooltip: 'Remove from queue',
                                      onPressed: () {
                                        if (ep.id != null) {
                                          audioHandler.removeFromQueue(ep.id!);
                                        }
                                      },
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(Icons.drag_handle, size: 20),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  audioHandler.playEpisode(ep);
                                },
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
}
