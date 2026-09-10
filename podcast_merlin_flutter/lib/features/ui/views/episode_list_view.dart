import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/podcast.dart';
import '../../../core/providers/app_providers.dart';
import '../widgets/cached_image.dart';
import '../widgets/purified_html_text.dart';
import '../widgets/sync_error_banner.dart';
import '../widgets/timestamped_description.dart';

class EpisodeListView extends ConsumerStatefulWidget {
  final Podcast? podcast;
  final VoidCallback? onBackPressed;

  const EpisodeListView({super.key, this.podcast, this.onBackPressed});

  @override
  ConsumerState<EpisodeListView> createState() => _EpisodeListViewState();
}

class _EpisodeListViewState extends ConsumerState<EpisodeListView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  EpisodeFilter? _localFilter;

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
    _searchController.dispose();
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
            initialValue: _localFilter ?? episodesState.filter,
            onSelected: (filter) {
              setState(() => _localFilter = filter);
              ref.read(episodesNotifierProvider(widget.podcast?.id).notifier).setFilter(filter);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: EpisodeFilter.all, child: Text('All Episodes')),
              PopupMenuItem(value: EpisodeFilter.unplayed, child: Text('Unplayed Only')),
              PopupMenuItem(value: EpisodeFilter.inProgress, child: Text('In Progress Only')),
              PopupMenuItem(value: EpisodeFilter.starred, child: Text('Starred Only')),
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

  void _selectFilter(EpisodeFilter filter) {
    setState(() => _localFilter = filter);
    ref.read(episodesNotifierProvider(widget.podcast?.id).notifier).setFilter(filter);
  }

  List<Episode> _filterEpisodes(List<Episode> rawList, EpisodeFilter filter, String query) {
    return rawList.where((e) {
      switch (filter) {
        case EpisodeFilter.unplayed:
          if (e.isPlayed) return false;
          break;
        case EpisodeFilter.inProgress:
          if (e.isPlayed || e.position <= 0) return false;
          break;
        case EpisodeFilter.starred:
          if (!e.isStarred) return false;
          break;
        case EpisodeFilter.finished:
          if (!e.isFinished) return false;
          break;
        case EpisodeFilter.downloaded:
          if (!e.isDownloaded) return false;
          break;
        case EpisodeFilter.all:
          break;
      }

      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        final titleMatch = e.title.toLowerCase().contains(q);
        final descMatch = e.description.toLowerCase().contains(q);
        if (!titleMatch && !descMatch) return false;
      }

      return true;
    }).toList();
  }

  Widget _buildSearchAndFilterControls(
    BuildContext context,
    EpisodeFilter activeFilter,
    int displayedCount,
    int totalCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search episodes by title or notes...',
              maintainHintSize: false,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (val) {
              setState(() => _searchQuery = val.trim());
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _EpisodeFilterChip(
                        key: const ValueKey('filter_all'),
                        label: 'All',
                        selected: activeFilter == EpisodeFilter.all,
                        onSelected: (_) => _selectFilter(EpisodeFilter.all),
                      ),
                      _EpisodeFilterChip(
                        key: const ValueKey('filter_unplayed'),
                        label: 'Unplayed',
                        selected: activeFilter == EpisodeFilter.unplayed,
                        onSelected: (_) => _selectFilter(EpisodeFilter.unplayed),
                      ),
                      _EpisodeFilterChip(
                        key: const ValueKey('filter_in_progress'),
                        label: 'In Progress',
                        selected: activeFilter == EpisodeFilter.inProgress,
                        onSelected: (_) => _selectFilter(EpisodeFilter.inProgress),
                      ),
                      _EpisodeFilterChip(
                        key: const ValueKey('filter_starred'),
                        label: 'Starred',
                        selected: activeFilter == EpisodeFilter.starred,
                        onSelected: (_) => _selectFilter(EpisodeFilter.starred),
                      ),
                      _EpisodeFilterChip(
                        key: const ValueKey('filter_downloaded'),
                        label: 'Downloaded',
                        selected: activeFilter == EpisodeFilter.downloaded,
                        onSelected: (_) => _selectFilter(EpisodeFilter.downloaded),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Showing $displayedCount of $totalCount episodes',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
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

    final activeFilter = _localFilter ?? episodesState.filter;
    final displayedEpisodes = _filterEpisodes(episodesState.episodes, activeFilter, _searchQuery);

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
          SliverToBoxAdapter(
            child: _buildSearchAndFilterControls(
              context,
              activeFilter,
              displayedEpisodes.length,
              episodesState.episodes.length,
            ),
          ),
          if (activeFilter == EpisodeFilter.downloaded && displayedEpisodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.download_done_rounded,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No downloaded episodes yet',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Download episodes to listen to them offline.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _localFilter = EpisodeFilter.all;
                          });
                          ref.read(episodesNotifierProvider(widget.podcast?.id).notifier).setFilter(EpisodeFilter.all);
                        },
                        child: const Text('Show All Episodes'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (episodesState.episodes.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No episodes found'),
                ),
              ),
            )
          else if (displayedEpisodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.search_off,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No episodes match your search / filter',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      if (activeFilter == EpisodeFilter.downloaded) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Download episodes to listen to them offline.',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _localFilter = EpisodeFilter.all;
                          });
                          ref.read(episodesNotifierProvider(widget.podcast?.id).notifier).setFilter(EpisodeFilter.all);
                        },
                        child: const Text('Clear Filters'),
                      ),
                    ],
                  ),
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
                    final ep = displayedEpisodes[itemIndex];
                    return _EpisodeTile(
                      episode: ep,
                      audioHandler: audioHandler,
                      onTap: () => _showEpisodeDetailsModal(context, ep),
                      onPlay: () => audioHandler.playEpisode(ep),
                      onToggleStar: () => ref
                          .read(episodesNotifierProvider(widget.podcast?.id).notifier)
                          .toggleStar(ep),
                      onDownload: () => ref
                          .read(episodeDownloadServiceProvider)
                          .startDownload(ep),
                      onCancelDownload: () {
                        if (ep.id != null) {
                          ref
                              .read(episodeDownloadServiceProvider)
                              .cancelDownload(ep.id!);
                        }
                      },
                      onDeleteDownload: () => ref
                          .read(episodeDownloadServiceProvider)
                          .deleteDownload(ep),
                    );
                  },
                  childCount: math.max(0, displayedEpisodes.length * 2 - 1),
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
                AppCachedImage(
                  imageUrl: podcast.imageUrl,
                  width: 80,
                  height: 80,
                  borderRadius: BorderRadius.circular(8),
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
    final currentEpisode = ref.read(audioHandlerProvider).currentEpisode;
    final isCurrent = currentEpisode?.mediaUrl == ep.mediaUrl;
    final effectiveEp = isCurrent ? (currentEpisode ?? ep) : ep;

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
                effectiveEp.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (effectiveEp.publishedAt != null)
                    Text(
                      'Published: ${DateFormat.yMMMMd().format(effectiveEp.publishedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (effectiveEp.isFinished) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Played',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: Icon(effectiveEp.isFinished ? Icons.replay : Icons.play_arrow),
                label: Text(effectiveEp.isFinished ? 'Replay Episode' : 'Play Episode'),
                onPressed: () {
                  Navigator.pop(modalCtx);
                  ref.read(audioHandlerProvider).playEpisode(effectiveEp);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.playlist_play),
                      label: const Text('Play Next'),
                      onPressed: () {
                        Navigator.pop(modalCtx);
                        ref.read(audioHandlerProvider).addToQueue(effectiveEp, playNext: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added "${effectiveEp.title}" as next up')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.queue_music),
                      label: const Text('Add to Queue'),
                      onPressed: () {
                        Navigator.pop(modalCtx);
                        ref.read(audioHandlerProvider).addToQueue(effectiveEp, playNext: false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added "${effectiveEp.title}" to queue')),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: Icon(
                  effectiveEp.isStarred ? Icons.star : Icons.star_border,
                  color: effectiveEp.isStarred ? Colors.amber : null,
                ),
                label: Text(effectiveEp.isStarred ? 'Unstar Episode' : 'Star Episode'),
                onPressed: () async {
                  final newStatus = await ref
                      .read(episodesNotifierProvider(widget.podcast?.id).notifier)
                      .toggleStar(effectiveEp);
                  if (modalCtx.mounted) {
                    Navigator.pop(modalCtx);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(newStatus ? 'Episode starred' : 'Episode unstarred'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              _buildModalDownloadButton(context, modalCtx, effectiveEp),
              const SizedBox(height: 16),
              const Text(
                'Description',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TimestampedDescription(
                text: effectiveEp.description,
                episode: effectiveEp,
                textStyle: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalDownloadButton(BuildContext context, BuildContext modalCtx, Episode ep) {
    if (ep.isDownloaded) {
      final mb = ep.downloadedBytes > 0
          ? '${(ep.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
          : 'Downloaded';
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        label: Text('Delete Download ($mb)'),
        onPressed: () async {
          Navigator.pop(modalCtx);
          await ref.read(episodeDownloadServiceProvider).deleteDownload(ep);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Deleted download for "${ep.title}"')),
            );
          }
        },
      );
    } else if (ep.isDownloading) {
      final pct = (ep.downloadProgress * 100).toStringAsFixed(0);
      return OutlinedButton.icon(
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text('Downloading ($pct%) • Tap to Cancel'),
        onPressed: () {
          Navigator.pop(modalCtx);
          if (ep.id != null) {
            ref.read(episodeDownloadServiceProvider).cancelDownload(ep.id!);
          }
        },
      );
    } else if (ep.downloadStatus == DownloadStatus.failed) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
        icon: const Icon(Icons.refresh, color: Colors.orange),
        label: const Text('Download Failed • Retry'),
        onPressed: () {
          Navigator.pop(modalCtx);
          ref.read(episodeDownloadServiceProvider).startDownload(ep);
        },
      );
    } else {
      return OutlinedButton.icon(
        icon: const Icon(Icons.download_outlined),
        label: const Text('Download Episode'),
        onPressed: () {
          Navigator.pop(modalCtx);
          ref.read(episodeDownloadServiceProvider).startDownload(ep);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Starting download for "${ep.title}"')),
          );
        },
      );
    }
  }
}

class _EpisodeTile extends StatelessWidget {
  final Episode episode;
  final dynamic audioHandler;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onToggleStar;
  final VoidCallback? onDownload;
  final VoidCallback? onCancelDownload;
  final VoidCallback? onDeleteDownload;

  const _EpisodeTile({
    required this.episode,
    required this.audioHandler,
    required this.onTap,
    required this.onPlay,
    required this.onToggleStar,
    this.onDownload,
    this.onCancelDownload,
    this.onDeleteDownload,
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildDownloadButton(BuildContext context) {
    if (episode.isDownloaded) {
      return IconButton(
        icon: Icon(
          Icons.download_done_rounded,
          color: Theme.of(context).colorScheme.primary,
          size: 22,
        ),
        tooltip: 'Downloaded (${_formatBytes(episode.downloadedBytes)})',
        onPressed: onDeleteDownload,
      );
    } else if (episode.isDownloading) {
      if (episode.downloadStatus == DownloadStatus.queued) {
        return IconButton(
          icon: const Icon(Icons.hourglass_top, size: 20, color: Colors.grey),
          tooltip: 'Queued for download • Tap to cancel',
          onPressed: onCancelDownload,
        );
      }
      return IconButton(
        icon: SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: episode.downloadProgress > 0 ? episode.downloadProgress : null,
                strokeWidth: 2.5,
              ),
              const Icon(Icons.close, size: 12),
            ],
          ),
        ),
        tooltip: 'Downloading (${(episode.downloadProgress * 100).toInt()}%) • Tap to cancel',
        onPressed: onCancelDownload,
      );
    } else if (episode.downloadStatus == DownloadStatus.failed) {
      return IconButton(
        icon: const Icon(Icons.refresh, color: Colors.orange, size: 22),
        tooltip: 'Download failed • Tap to retry',
        onPressed: onDownload,
      );
    } else {
      return IconButton(
        icon: const Icon(Icons.download_outlined, size: 22),
        tooltip: 'Download episode',
        onPressed: onDownload,
      );
    }
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
          bool isCurrentEpisodePlayed = false;
          try {
            if (audioHandler?.currentEpisode != null) {
              isCurrentEpisodePlayed = audioHandler.currentEpisode.isPlayed;
            }
          } catch (_) {}

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

          if (isCurrentEpisodePlayed) {
            isFinished = true;
          } else if (displayPosition > 0 && displayDuration > 0) {
            if (displayDuration > 60) {
              isFinished = (displayDuration - displayPosition) <= 60;
            } else {
              isFinished = displayPosition >= (displayDuration > 10 ? displayDuration - 10 : displayDuration);
            }
          } else {
            isFinished = false;
          }
        }

        double progressPercentage = 0.0;
        if (displayDuration > 0) {
          progressPercentage = (displayPosition / displayDuration).clamp(0.0, 1.0);
        }

        final showProgress = displayPosition > 0 && !isFinished;

        final tile = ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Stack(
            children: [
              AppCachedImage(
                imageUrl: episode.imageUrl,
                width: 56,
                height: 56,
                borderRadius: BorderRadius.circular(6),
              ),
              if (isFinished)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            episode.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent
                  ? Theme.of(context).colorScheme.primary
                  : (isFinished ? Theme.of(context).disabledColor : null),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  if (isFinished) ...[
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Played • ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  Text(
                    episode.publishedAt != null
                        ? DateFormat.yMMMd().format(episode.publishedAt!)
                        : 'Unknown Date',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isFinished ? Theme.of(context).disabledColor : null,
                        ),
                  ),
                  if ((displayPosition > 0 || isCurrent) && displayDuration > 0 && !isFinished) ...[
                    const SizedBox(width: 8),
                    Text(
                      '• ${_formatDuration(displayPosition)} / ${_formatDuration(displayDuration)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                          ),
                    ),
                  ] else if (displayDuration > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '• ${_formatDuration(displayDuration)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isFinished ? Theme.of(context).disabledColor : null,
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDownloadButton(context),
              IconButton(
                icon: Icon(
                  episode.isStarred ? Icons.star : Icons.star_border,
                  color: episode.isStarred ? Colors.amber : null,
                ),
                tooltip: episode.isStarred ? 'Unstar episode' : 'Star episode',
                onPressed: onToggleStar,
              ),
              IconButton(
                icon: Icon(
                  isCurrent
                      ? Icons.volume_up
                      : (isFinished ? Icons.replay_rounded : Icons.play_arrow_rounded),
                  size: 32,
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : (isFinished
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary),
                ),
                tooltip: isCurrent
                    ? 'Now playing'
                    : (isFinished ? 'Replay episode' : 'Play episode'),
                onPressed: onPlay,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (value) {
                  if (value == 'download') {
                    onDownload?.call();
                  } else if (value == 'cancel_download') {
                    onCancelDownload?.call();
                  } else if (value == 'delete_download') {
                    onDeleteDownload?.call();
                  } else if (value == 'star') {
                    onToggleStar();
                  } else if (value == 'play_next') {
                    audioHandler?.addToQueue(episode, playNext: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Playing next: ${episode.title}')),
                    );
                  } else if (value == 'add_queue') {
                    audioHandler?.addToQueue(episode, playNext: false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added to queue: ${episode.title}')),
                    );
                  }
                },
                itemBuilder: (context) => [
                  if (episode.isDownloaded)
                    const PopupMenuItem(
                      value: 'delete_download',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Delete Download', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    )
                  else if (episode.isDownloading)
                    const PopupMenuItem(
                      value: 'cancel_download',
                      child: Row(
                        children: [
                          Icon(Icons.close, size: 20),
                          SizedBox(width: 12),
                          Text('Cancel Download'),
                        ],
                      ),
                    )
                  else
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Download Episode'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'star',
                    child: Row(
                      children: [
                        Icon(
                          episode.isStarred ? Icons.star : Icons.star_border,
                          size: 20,
                          color: episode.isStarred ? Colors.amber : null,
                        ),
                        const SizedBox(width: 12),
                        Text(episode.isStarred ? 'Unstar Episode' : 'Star Episode'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'play_next',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_play, size: 20),
                        SizedBox(width: 12),
                        Text('Play Next'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add_queue',
                    child: Row(
                      children: [
                        Icon(Icons.queue_music, size: 20),
                        SizedBox(width: 12),
                        Text('Add to Queue'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: onTap,
        );

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: isFinished ? 0.45 : 1.0,
          child: tile,
        );
      },
    );
  }
}

class _EpisodeFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _EpisodeFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = selected
        ? colorScheme.secondaryContainer
        : colorScheme.surface;
    final textColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final borderColor = selected
        ? colorScheme.secondaryContainer
        : colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelected(!selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 14, color: textColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
