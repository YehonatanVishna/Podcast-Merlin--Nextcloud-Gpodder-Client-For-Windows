import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/podcast.dart';
import '../../../core/providers/app_providers.dart';
import '../widgets/purified_html_text.dart';
import '../widgets/sync_error_banner.dart';

class EpisodeListView extends ConsumerStatefulWidget {
  final Podcast? podcast;
  final VoidCallback? onBackPressed;

  const EpisodeListView({super.key, this.podcast, this.onBackPressed});

  @override
  ConsumerState<EpisodeListView> createState() => _EpisodeListViewState();
}

class _EpisodeListViewState extends ConsumerState<EpisodeListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant EpisodeListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.podcast?.id != widget.podcast?.id) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 300) {
      ref.read(episodesNotifierProvider(widget.podcast?.id).notifier).loadMoreEpisodes();
    }
  }

  void _checkAutoLoadMore(EpisodesState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent <= 0 &&
          state.hasMore &&
          !state.isLoading &&
          !state.isLoadingMore) {
        ref.read(episodesNotifierProvider(widget.podcast?.id).notifier).loadMoreEpisodes();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final episodesState = ref.watch(episodesNotifierProvider(widget.podcast?.id));
    final audioHandler = ref.watch(audioHandlerProvider);
    final syncStatus = ref.watch(syncStatusNotifierProvider);

    _checkAutoLoadMore(episodesState);

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBackPressed != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: widget.onBackPressed,
              )
            : null,
        title: Text(widget.podcast?.title ?? 'All Episodes'),
        actions: [
          IconButton(
            icon: syncStatus.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.refresh),
            tooltip: syncStatus.isSyncing
                ? (syncStatus.currentTask ?? 'Refreshing...')
                : 'Refresh Feed',
            onPressed: syncStatus.isSyncing
                ? null
                : () {
                    ref
                        .read(episodesNotifierProvider(widget.podcast?.id).notifier)
                        .refresh(podcast: widget.podcast);
                  },
          ),
          PopupMenuButton<EpisodeFilter>(
            icon: const Icon(Icons.filter_list),
            initialValue: episodesState.filter,
            onSelected: (filter) {
              ref.read(episodesNotifierProvider(widget.podcast?.id).notifier).setFilter(filter);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: EpisodeFilter.all, child: Text('All Episodes')),
              PopupMenuItem(value: EpisodeFilter.unplayed, child: Text('Unplayed Only')),
              PopupMenuItem(value: EpisodeFilter.finished, child: Text('Finished Only')),
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
              onRetry: () => ref
                  .read(episodesNotifierProvider(widget.podcast?.id).notifier)
                  .refresh(podcast: widget.podcast),
            ),
          ],
          if (widget.podcast != null && (widget.podcast!.isDead || widget.podcast!.lastFeedError != null)) ...[
            SyncErrorBanner(
              errorMessage: 'Feed unreachable: ${widget.podcast!.lastFeedError ?? "This RSS feed is dead or inaccessible."}',
              onRetry: () => ref
                  .read(episodesNotifierProvider(widget.podcast?.id).notifier)
                  .refresh(podcast: widget.podcast),
            ),
          ],
          if (episodesState.error != null && episodesState.episodes.isNotEmpty)
            SyncErrorBanner(
              errorMessage: episodesState.error!,
              onRetry: () => ref
                  .read(episodesNotifierProvider(widget.podcast?.id).notifier)
                  .loadMoreEpisodes(),
            ),
          Expanded(child: _buildBody(context, episodesState, audioHandler)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, EpisodesState episodesState, dynamic audioHandler) {
    if (episodesState.isLoading && episodesState.episodes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (episodesState.error != null && episodesState.episodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                'Error loading episodes: ${episodesState.error}',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(episodesNotifierProvider(widget.podcast?.id).notifier)
                    .refresh(podcast: widget.podcast);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(episodesNotifierProvider(widget.podcast?.id).notifier)
            .refresh(podcast: widget.podcast);
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.podcast != null)
            SliverToBoxAdapter(
              child: _buildPodcastHeader(context, widget.podcast!, episodesState.episodes.length),
            ),
          if (episodesState.episodes.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No episodes found'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index.isOdd) {
                      return const Divider(height: 1, indent: 16, endIndent: 16);
                    }
                    final itemIndex = index ~/ 2;
                    final ep = episodesState.episodes[itemIndex];
                    return _EpisodeTile(
                      episode: ep,
                      audioHandler: audioHandler,
                      onTap: () => _showEpisodeDetailsModal(context, ep),
                      onPlay: () => audioHandler.playEpisode(ep),
                    );
                  },
                  childCount: math.max(0, episodesState.episodes.length * 2 - 1),
                ),
              ),
            ),
          if (episodesState.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            )
          else if (!episodesState.hasMore && episodesState.episodes.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'No more episodes',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPodcastHeader(BuildContext context, Podcast podcast, int loadedCount) {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: podcast.imageUrl.isNotEmpty
                      ? Image.network(
                          podcast.imageUrl,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 80,
                            height: 80,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(Icons.podcasts, size: 40),
                          ),
                        )
                      : Container(
                          width: 80,
                          height: 80,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.podcasts, size: 40),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        podcast.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      if (podcast.link.isNotEmpty)
                        Text(
                          podcast.link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      const SizedBox(height: 8),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.feed, size: 16),
                        label: Text(
                          '$loadedCount episodes loaded',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (podcast.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              PurifiedHtmlText(
                htmlData: podcast.description,
                textStyle: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
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
              PurifiedHtmlText(
                htmlData: ep.description,
                textStyle: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Episode episode;
  final dynamic audioHandler;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _EpisodeTile({
    required this.episode,
    required this.audioHandler,
    required this.onTap,
    required this.onPlay,
  });

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$secs';
    }
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    Stream<PlaybackState>? playbackStream;
    try {
      if (audioHandler is BaseAudioHandler) {
        playbackStream = (audioHandler as BaseAudioHandler).playbackState;
      } else if (audioHandler != null && audioHandler.playbackState is Stream<PlaybackState>) {
        playbackStream = audioHandler.playbackState as Stream<PlaybackState>;
      }
    } catch (_) {}

    return StreamBuilder<PlaybackState>(
      stream: playbackStream,
      builder: (context, snapshot) {
        final playbackState = snapshot.data;
        String? currentMediaUrl;
        try {
          currentMediaUrl = audioHandler?.currentEpisode?.mediaUrl;
        } catch (_) {}

        final isCurrent = currentMediaUrl == episode.mediaUrl;

        int displayPosition = episode.position;
        int displayDuration = episode.duration;
        bool isFinished = episode.isFinished;

        if (isCurrent) {
          if (playbackState != null) {
            displayPosition = playbackState.position.inSeconds;
          } else {
            try {
              if (audioHandler?.currentEpisode?.position != null) {
                displayPosition = audioHandler.currentEpisode.position;
              }
            } catch (_) {}
          }
          int handlerDuration = 0;
          try {
            handlerDuration = audioHandler?.mediaItem?.value?.duration?.inSeconds ?? 0;
          } catch (_) {}

          if (displayDuration <= 0 && handlerDuration > 0) {
            displayDuration = handlerDuration;
          }
          if (displayDuration > 0 && displayPosition >= (displayDuration - 10)) {
            isFinished = true;
          }
        }

        double progressPercentage = 0.0;
        if (displayDuration > 0) {
          progressPercentage = (displayPosition / displayDuration).clamp(0.0, 1.0);
        }

        final showProgress = displayPosition > 0 && !isFinished;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: episode.imageUrl.isNotEmpty
                ? Image.network(
                    episode.imageUrl,
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
            episode.title,
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
              Row(
                children: [
                  Text(
                    episode.publishedAt != null
                        ? DateFormat.yMMMd().format(episode.publishedAt!)
                        : 'Unknown Date',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (displayPosition > 0 && displayDuration > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '• ${_formatDuration(displayPosition)} / ${_formatDuration(displayDuration)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                          ),
                    ),
                  ],
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progressPercentage,
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
            onPressed: onPlay,
          ),
          onTap: onTap,
        );
      },
    );
  }
}
