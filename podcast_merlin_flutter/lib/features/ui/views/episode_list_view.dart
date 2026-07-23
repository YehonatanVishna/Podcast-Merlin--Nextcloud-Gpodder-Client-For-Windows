import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/podcast.dart';
import '../../../core/providers/app_providers.dart';

enum EpisodeFilter { all, unplayed, finished }

class EpisodeListView extends ConsumerStatefulWidget {
  final Podcast? podcast;

  const EpisodeListView({super.key, this.podcast});

  @override
  ConsumerState<EpisodeListView> createState() => _EpisodeListViewState();
}

class _EpisodeListViewState extends ConsumerState<EpisodeListView> {
  EpisodeFilter _filter = EpisodeFilter.all;

  @override
  Widget build(BuildContext context) {
    final episodesState = ref.watch(episodesNotifierProvider(widget.podcast?.id));
    final audioHandler = ref.watch(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.podcast?.title ?? 'All Episodes'),
        actions: [
          PopupMenuButton<EpisodeFilter>(
            icon: const Icon(Icons.filter_list),
            initialValue: _filter,
            onSelected: (filter) {
              setState(() {
                _filter = filter;
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: EpisodeFilter.all, child: Text('All Episodes')),
              PopupMenuItem(value: EpisodeFilter.unplayed, child: Text('Unplayed Only')),
              PopupMenuItem(value: EpisodeFilter.finished, child: Text('Finished Only')),
            ],
          ),
        ],
      ),
      body: episodesState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading episodes: $err')),
        data: (episodes) {
          final filteredEpisodes = episodes.where((ep) {
            if (_filter == EpisodeFilter.unplayed) return !ep.isFinished;
            if (_filter == EpisodeFilter.finished) return ep.isFinished;
            return true;
          }).toList();

          if (filteredEpisodes.isEmpty) {
            return const Center(child: Text('No episodes found'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: filteredEpisodes.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final ep = filteredEpisodes[index];
              final isCurrent = audioHandler.currentEpisode?.mediaUrl == ep.mediaUrl;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: ep.imageUrl.isNotEmpty
                      ? Image.network(
                          ep.imageUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 56,
                            height: 56,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(Icons.podcasts),
                          ),
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.podcasts),
                        ),
                ),
                title: Text(
                  ep.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      ep.publishedAt != null
                          ? DateFormat.yMMMd().format(ep.publishedAt!)
                          : 'Unknown Date',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (ep.position > 0 && !ep.isFinished) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: ep.progressPercentage,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ],
                ),
                trailing: IconButton(
                  icon: Icon(
                    isCurrent ? Icons.volume_up : Icons.play_arrow_rounded,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () {
                    audioHandler.playEpisode(ep);
                  },
                ),
                onTap: () {
                  _showEpisodeDetailsModal(context, ep);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showEpisodeDetailsModal(BuildContext context, Episode ep) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: ListView(
            controller: scrollController,
            children: [
              Text(
                ep.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (ep.publishedAt != null)
                Text(
                  'Published: ${DateFormat.yMMMMd().format(ep.publishedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play Episode'),
                onPressed: () {
                  Navigator.pop(modalCtx);
                  ref.read(audioHandlerProvider).playEpisode(ep);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Description',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                ep.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
