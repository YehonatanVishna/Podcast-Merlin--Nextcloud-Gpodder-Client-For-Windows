import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/responsive.dart';
import '../../downloads/episode_download_service.dart';
import '../widgets/cached_image.dart';

enum DownloadSortOption { newest, oldest, largest, smallest, title }

class DownloadCenterView extends ConsumerStatefulWidget {
  const DownloadCenterView({super.key});

  @override
  ConsumerState<DownloadCenterView> createState() => _DownloadCenterViewState();
}

class _DownloadCenterViewState extends ConsumerState<DownloadCenterView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DownloadSortOption _sortOption = DownloadSortOption.newest;

  bool _isSelectionMode = false;
  final Set<int> _selectedEpisodeIds = <int>{};
  bool _isFailedSelectionMode = false;
  final Set<int> _selectedFailedIds = <int>{};
  final Map<int, Episode> _episodeMetaCache = {};

  Future<void> _loadEpisodeMeta(int episodeId) async {
    if (_episodeMetaCache.containsKey(episodeId)) return;
    final ep = await DatabaseHelper.instance.getEpisodeById(episodeId);
    if (ep != null && mounted) {
      setState(() {
        _episodeMetaCache[episodeId] = ep;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        if (_isSelectionMode || _isFailedSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedEpisodeIds.clear();
            _isFailedSelectionMode = false;
            _selectedFailedIds.clear();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    return '${_formatBytes(bytesPerSec)}/s';
  }

  String _formatEta(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    if (seconds < 60) return '${seconds}s left';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s left';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  List<Episode> _sortDownloadedEpisodes(List<Episode> episodes) {
    final list = List<Episode>.from(episodes);
    switch (_sortOption) {
      case DownloadSortOption.newest:
        list.sort((a, b) => (b.publishedAt ?? DateTime(1970))
            .compareTo(a.publishedAt ?? DateTime(1970)));
        break;
      case DownloadSortOption.oldest:
        list.sort((a, b) => (a.publishedAt ?? DateTime(1970))
            .compareTo(b.publishedAt ?? DateTime(1970)));
        break;
      case DownloadSortOption.largest:
        list.sort((a, b) => b.downloadedBytes.compareTo(a.downloadedBytes));
        break;
      case DownloadSortOption.smallest:
        list.sort((a, b) => a.downloadedBytes.compareTo(b.downloadedBytes));
        break;
      case DownloadSortOption.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = context.isCompact;
    final downloadService = ref.watch(episodeDownloadServiceProvider);
    final activeCountAsync = ref.watch(activeDownloadsCountProvider);
    final storageAsync = ref.watch(downloadStorageUsageBytesProvider);
    final downloadedListAsync = ref.watch(downloadedEpisodesListProvider);
    final failedListAsync = ref.watch(failedEpisodesListProvider);
    final tasksMapAsync = ref.watch(downloadTasksStreamProvider);

    final activeCount = activeCountAsync.valueOrNull ?? downloadService.activeAndQueuedCount;
    final downloadedList = downloadedListAsync.valueOrNull ?? [];
    final failedList = failedListAsync.valueOrNull ?? [];
    final tasksMap = tasksMapAsync.valueOrNull ?? downloadService.currentTasks;

    // Filter downloaded by search
    final filteredDownloaded = downloadedList.where((ep) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return ep.title.toLowerCase().contains(q) ||
          ep.description.toLowerCase().contains(q);
    }).toList();
    final sortedDownloaded = _sortDownloadedEpisodes(filteredDownloaded);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded, size: 24),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Download Center',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (activeCount > 0)
            IconButton(
              icon: const Icon(Icons.pause_circle_outline),
              tooltip: 'Pause All Active Downloads',
              onPressed: () => downloadService.pauseAll(),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Resume All Paused Downloads',
              onPressed: () => downloadService.resumeAll(),
            ),
          if (failedList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.replay),
              tooltip: 'Retry All Failed (${failedList.length})',
              onPressed: () => downloadService.retryAllFailed(),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'cancel_all') {
                downloadService.cancelAllActive();
              } else if (val == 'clear_all') {
                _showClearAllDialog(context);
              } else if (val == 'refresh') {
                ref.invalidate(downloadStorageUsageBytesProvider);
                ref.invalidate(downloadedEpisodesListProvider);
                ref.invalidate(failedEpisodesListProvider);
              }
            },
            itemBuilder: (context) => [
              if (activeCount > 0)
                const PopupMenuItem(
                  value: 'cancel_all',
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Cancel All Active'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 10),
                    Text('Refresh Status'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Clear All Downloads', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            isScrollable: isCompact,
            tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Queue & Active'),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 6),
                      Badge.count(
                        count: activeCount,
                        backgroundColor: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Downloaded'),
                    if (downloadedList.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge.count(
                        count: downloadedList.length,
                        backgroundColor: theme.colorScheme.secondary,
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Failed'),
                    if (failedList.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge.count(
                        count: failedList.length,
                        backgroundColor: Colors.red,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _buildStorageSummaryHeader(context, storageAsync, downloadedList.length, activeCount),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildQueueTab(context, downloadService, tasksMap),
                _buildDownloadedTab(context, sortedDownloaded, downloadService),
                _buildFailedTab(context, failedList, downloadService),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSummaryHeader(
    BuildContext context,
    AsyncValue<int> storageAsync,
    int downloadedCount,
    int activeCount,
  ) {
    final theme = Theme.of(context);
    final storageBytes = storageAsync.valueOrNull ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_formatBytes(storageBytes)} offline storage • $downloadedCount ${downloadedCount == 1 ? 'episode' : 'episodes'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          if (activeCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$activeCount active',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
  }

  Widget _buildQueueTab(
    BuildContext context,
    EpisodeDownloadService service,
    Map<int, DownloadTaskEvent> tasksMap,
  ) {
    final theme = Theme.of(context);
    final activeEntries = tasksMap.entries
        .where((e) =>
            e.value.status == DownloadStatus.downloading ||
            e.value.status == DownloadStatus.queued ||
            e.value.status == DownloadStatus.paused)
        .toList();

    if (activeEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_done_rounded, size: 64, color: theme.disabledColor),
              const SizedBox(height: 16),
              Text(
                'No Active Downloads',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Episodes you choose to download will appear here with live speed and progress.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
      );
    }

    final hasDownloading = activeEntries.any((e) => e.value.status == DownloadStatus.downloading);
    final hasPaused = activeEntries.any((e) => e.value.status == DownloadStatus.paused);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 480;

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Active Downloads (${activeEntries.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (hasDownloading)
                    isNarrow
                        ? IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.pause, size: 18),
                            tooltip: 'Pause All',
                            onPressed: () => service.pauseAll(),
                          )
                        : FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            ),
                            icon: const Icon(Icons.pause, size: 16),
                            label: const Text('Pause All'),
                            onPressed: () => service.pauseAll(),
                          )
                  else if (hasPaused)
                    isNarrow
                        ? IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            tooltip: 'Resume All',
                            onPressed: () => service.resumeAll(),
                          )
                        : FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            ),
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: const Text('Resume All'),
                            onPressed: () => service.resumeAll(),
                          ),
                  const SizedBox(width: 8),
                  isNarrow
                      ? IconButton.outlined(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Cancel All',
                          onPressed: () => _confirmCancelAllActive(context, service),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Cancel All'),
                          onPressed: () => _confirmCancelAllActive(context, service),
                        ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: activeEntries.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final entry = activeEntries[idx];
              final event = entry.value;

              if (event.episodeTitle == null && !_episodeMetaCache.containsKey(event.episodeId)) {
                _loadEpisodeMeta(event.episodeId);
              }
              final cachedEp = _episodeMetaCache[event.episodeId];
              final displayTitle = event.episodeTitle ?? cachedEp?.title ?? 'Episode #${event.episodeId}';
              final displayImageUrl = (event.imageUrl != null && event.imageUrl!.isNotEmpty)
                  ? event.imageUrl
                  : cachedEp?.imageUrl;

              Widget leadingWidget;
              if (displayImageUrl != null && displayImageUrl.isNotEmpty) {
                leadingWidget = Stack(
                  children: [
                    AppCachedImage(
                      imageUrl: displayImageUrl,
                      width: 48,
                      height: 48,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    if (event.status == DownloadStatus.paused)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.pause, color: Colors.white, size: 22),
                        ),
                      ),
                  ],
                );
              } else {
                leadingWidget = Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: event.status == DownloadStatus.paused
                        ? const Icon(Icons.pause, size: 22)
                        : const Icon(Icons.downloading, size: 22),
                  ),
                );
              }

              return ListTile(
                leading: leadingWidget,
                title: Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: event.progress > 0 ? event.progress : null,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${(event.progress * 100).toStringAsFixed(0)}% • ${_formatBytes(event.downloadedBytes)} / ${_formatBytes(event.totalBytes)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Spacer(),
                        if (event.bytesPerSecond > 0)
                          Text(
                            _formatSpeed(event.bytesPerSecond),
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        if (event.estimatedSecondsRemaining != null &&
                            event.estimatedSecondsRemaining! > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• ${_formatEta(event.estimatedSecondsRemaining)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (event.status == DownloadStatus.downloading)
                      IconButton(
                        icon: const Icon(Icons.pause_circle_outline),
                        tooltip: 'Pause Download',
                        onPressed: () => service.pauseDownload(event.episodeId),
                      )
                    else if (event.status == DownloadStatus.paused)
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline),
                        tooltip: 'Resume Download',
                        onPressed: () async {
                          final ep = await DatabaseHelper.instance.getEpisodeById(event.episodeId);
                          if (ep != null) {
                            await service.resumeDownload(ep);
                          }
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel Download',
                      onPressed: () => service.cancelDownload(event.episodeId),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmCancelAllActive(BuildContext context, EpisodeDownloadService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel All Downloads?'),
        content: const Text(
          'Are you sure you want to cancel all active and queued downloads? Incomplete download files will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Downloading'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.cancelAllActive();
    }
  }

  Widget _buildDownloadedTab(
    BuildContext context,
    List<Episode> episodes,
    EpisodeDownloadService service,
  ) {
    final theme = Theme.of(context);
    final audioHandler = ref.watch(audioHandlerProvider);

    final selectedBytes = episodes
        .where((e) => e.id != null && _selectedEpisodeIds.contains(e.id))
        .fold<int>(0, (sum, e) => sum + e.downloadedBytes);
    final allSelected = episodes.isNotEmpty &&
        episodes.every((e) => e.id != null && _selectedEpisodeIds.contains(e.id));

    return Column(
      children: [
        if (_isSelectionMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: allSelected
                      ? true
                      : (_selectedEpisodeIds.isNotEmpty ? null : false),
                  onChanged: (val) {
                    setState(() {
                      if (allSelected) {
                        _selectedEpisodeIds.clear();
                      } else {
                        _selectedEpisodeIds.addAll(
                          episodes.where((e) => e.id != null).map((e) => e.id!),
                        );
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_selectedEpisodeIds.length} of ${episodes.length} selected',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (selectedBytes > 0)
                        Text(
                          _formatBytes(selectedBytes),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(
                    _selectedEpisodeIds.isEmpty
                        ? 'Delete'
                        : 'Delete (${_selectedEpisodeIds.length})',
                  ),
                  onPressed: _selectedEpisodeIds.isEmpty
                      ? null
                      : () => _confirmDeleteSelected(context, episodes, service),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Cancel selection',
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedEpisodeIds.clear();
                    });
                  },
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search downloaded episodes...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
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
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.checklist_rounded),
                  tooltip: 'Select episodes to manage',
                  onPressed: episodes.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _isSelectionMode = true;
                            _selectedEpisodeIds.clear();
                          });
                        },
                ),
                const SizedBox(width: 4),
                PopupMenuButton<DownloadSortOption>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort episodes',
                  initialValue: _sortOption,
                  onSelected: (opt) => setState(() => _sortOption = opt),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: DownloadSortOption.newest,
                      child: Text('Date (Newest first)'),
                    ),
                    PopupMenuItem(
                      value: DownloadSortOption.oldest,
                      child: Text('Date (Oldest first)'),
                    ),
                    PopupMenuItem(
                      value: DownloadSortOption.largest,
                      child: Text('File Size (Largest first)'),
                    ),
                    PopupMenuItem(
                      value: DownloadSortOption.smallest,
                      child: Text('File Size (Smallest first)'),
                    ),
                    PopupMenuItem(
                      value: DownloadSortOption.title,
                      child: Text('Title (A-Z)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: episodes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open_outlined, size: 64, color: theme.disabledColor),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty ? 'No Matching Downloads' : 'No Downloaded Episodes',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Try adjusting your search keywords.'
                              : 'Episodes you download for offline playback will appear here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: episodes.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final ep = episodes[idx];
                    final isSelected = ep.id != null && _selectedEpisodeIds.contains(ep.id);
                    final dateStr = ep.publishedAt != null
                        ? DateFormat.yMMMd().format(ep.publishedAt!)
                        : '';
                    final durationStr = _formatDuration(ep.duration);

                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          setState(() {
                            _isSelectionMode = true;
                            if (ep.id != null) _selectedEpisodeIds.add(ep.id!);
                          });
                        }
                      },
                      onTap: _isSelectionMode
                          ? () {
                              if (ep.id == null) return;
                              setState(() {
                                if (_selectedEpisodeIds.contains(ep.id)) {
                                  _selectedEpisodeIds.remove(ep.id);
                                } else {
                                  _selectedEpisodeIds.add(ep.id!);
                                }
                              });
                            }
                          : () => audioHandler.playEpisode(ep),
                      leading: _isSelectionMode
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (val) {
                                    if (ep.id == null) return;
                                    setState(() {
                                      if (val == true) {
                                        _selectedEpisodeIds.add(ep.id!);
                                      } else {
                                        _selectedEpisodeIds.remove(ep.id!);
                                      }
                                    });
                                  },
                                ),
                                AppCachedImage(
                                  imageUrl: ep.imageUrl,
                                  width: 44,
                                  height: 44,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ],
                            )
                          : AppCachedImage(
                              imageUrl: ep.imageUrl,
                              width: 48,
                              height: 48,
                              borderRadius: BorderRadius.circular(8),
                            ),
                      title: Text(
                        ep.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          if (dateStr.isNotEmpty)
                            Text(dateStr, style: theme.textTheme.bodySmall),
                          if (dateStr.isNotEmpty && (durationStr.isNotEmpty || ep.downloadedBytes > 0))
                            const Text('•', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          if (durationStr.isNotEmpty)
                            Text(durationStr, style: theme.textTheme.bodySmall),
                          if (durationStr.isNotEmpty && ep.downloadedBytes > 0)
                            const Text('•', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text(
                            _formatBytes(ep.downloadedBytes),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      trailing: _isSelectionMode
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  tooltip: 'Play Offline',
                                  onPressed: () => audioHandler.playEpisode(ep),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  tooltip: 'Delete Download',
                                  onPressed: () async {
                                    await service.deleteDownload(ep);
                                    ref.invalidate(downloadStorageUsageBytesProvider);
                                    ref.invalidate(downloadedEpisodesListProvider);
                                    ref.invalidate(downloadedEpisodesCountProvider);
                                  },
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteSelected(
    BuildContext context,
    List<Episode> episodes,
    EpisodeDownloadService service,
  ) async {
    final toDelete = episodes.where((e) => e.id != null && _selectedEpisodeIds.contains(e.id)).toList();
    if (toDelete.isEmpty) return;

    final totalBytes = toDelete.fold<int>(0, (sum, e) => sum + e.downloadedBytes);
    final sizeStr = _formatBytes(totalBytes);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${toDelete.length} Downloads?'),
        content: Text(
          'This will permanently delete ${toDelete.length} downloaded audio ${toDelete.length == 1 ? "file" : "files"} ($sizeStr) from your local device storage. Your playback history and subscriptions will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete (${toDelete.length})'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final deleted = await service.deleteMultipleDownloads(toDelete);
      if (!mounted) return;
      ref.invalidate(downloadStorageUsageBytesProvider);
      ref.invalidate(downloadedEpisodesListProvider);
      ref.invalidate(downloadedEpisodesCountProvider);
      setState(() {
        _selectedEpisodeIds.clear();
        _isSelectionMode = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deleted $deleted downloaded ${deleted == 1 ? 'file' : 'files'} ($sizeStr freed)',
            ),
          ),
        );
      }
    }
  }

  Widget _buildFailedTab(
    BuildContext context,
    List<Episode> failedEpisodes,
    EpisodeDownloadService service,
  ) {
    final theme = Theme.of(context);

    if (failedEpisodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: Colors.green[400]),
              const SizedBox(height: 16),
              Text(
                'No Failed Downloads',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'All downloads have succeeded without errors.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
      );
    }

    final allFailedSelected = failedEpisodes.isNotEmpty &&
        failedEpisodes.every((e) => e.id != null && _selectedFailedIds.contains(e.id));

    return Column(
      children: [
        if (_isFailedSelectionMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: allFailedSelected
                      ? true
                      : (_selectedFailedIds.isNotEmpty ? null : false),
                  onChanged: (val) {
                    setState(() {
                      if (allFailedSelected) {
                        _selectedFailedIds.clear();
                      } else {
                        _selectedFailedIds.addAll(
                          failedEpisodes.where((e) => e.id != null).map((e) => e.id!),
                        );
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedFailedIds.length} of ${failedEpisodes.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.replay, size: 16),
                  label: Text('Retry (${_selectedFailedIds.length})'),
                  onPressed: _selectedFailedIds.isEmpty
                      ? null
                      : () async {
                          final toRetry = failedEpisodes
                              .where((e) => e.id != null && _selectedFailedIds.contains(e.id))
                              .toList();
                          for (final ep in toRetry) {
                            await service.retryFailed(ep);
                          }
                          ref.invalidate(failedEpisodesListProvider);
                          setState(() {
                            _selectedFailedIds.clear();
                            _isFailedSelectionMode = false;
                          });
                        },
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Dismiss (${_selectedFailedIds.length})'),
                  onPressed: _selectedFailedIds.isEmpty
                      ? null
                      : () async {
                          final toDismiss = failedEpisodes
                              .where((e) => e.id != null && _selectedFailedIds.contains(e.id))
                              .toList();
                          for (final ep in toDismiss) {
                            if (ep.id != null) {
                              await DatabaseHelper.instance.clearEpisodeDownload(ep.id!);
                            }
                          }
                          ref.invalidate(failedEpisodesListProvider);
                          setState(() {
                            _selectedFailedIds.clear();
                            _isFailedSelectionMode = false;
                          });
                        },
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Cancel selection',
                  onPressed: () {
                    setState(() {
                      _isFailedSelectionMode = false;
                      _selectedFailedIds.clear();
                    });
                  },
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Failed Downloads (${failedEpisodes.length})',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.checklist_rounded),
                  tooltip: 'Select failed downloads',
                  onPressed: () => setState(() => _isFailedSelectionMode = true),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: failedEpisodes.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final ep = failedEpisodes[idx];
              final isSelected = ep.id != null && _selectedFailedIds.contains(ep.id);

              return ListTile(
                selected: isSelected,
                selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                onLongPress: () {
                  if (!_isFailedSelectionMode) {
                    setState(() {
                      _isFailedSelectionMode = true;
                      if (ep.id != null) _selectedFailedIds.add(ep.id!);
                    });
                  }
                },
                onTap: _isFailedSelectionMode
                    ? () {
                        if (ep.id == null) return;
                        setState(() {
                          if (_selectedFailedIds.contains(ep.id)) {
                            _selectedFailedIds.remove(ep.id);
                          } else {
                            _selectedFailedIds.add(ep.id!);
                          }
                        });
                      }
                    : null,
                leading: _isFailedSelectionMode
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: isSelected,
                            onChanged: (val) {
                              if (ep.id == null) return;
                              setState(() {
                                if (val == true) {
                                  _selectedFailedIds.add(ep.id!);
                                } else {
                                  _selectedFailedIds.remove(ep.id!);
                                }
                              });
                            },
                          ),
                          AppCachedImage(
                            imageUrl: ep.imageUrl,
                            width: 44,
                            height: 44,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      )
                    : AppCachedImage(
                        imageUrl: ep.imageUrl,
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(8),
                      ),
                title: Text(
                  ep.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.error_outline, size: 14, color: Colors.red),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ep.downloadError ?? 'Download failed',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: _isFailedSelectionMode
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay),
                            tooltip: 'Retry Download',
                            onPressed: () async {
                              await service.retryFailed(ep);
                              ref.invalidate(failedEpisodesListProvider);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Dismiss',
                            onPressed: () async {
                              if (ep.id != null) {
                                await DatabaseHelper.instance.clearEpisodeDownload(ep.id!);
                                ref.invalidate(failedEpisodesListProvider);
                              }
                            },
                          ),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showClearAllDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Downloads?'),
        content: const Text(
          'This will delete all downloaded audio files from your device. Your playback history and subscriptions will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await ref.read(episodeDownloadServiceProvider).clearAllDownloads();
      ref.invalidate(downloadStorageUsageBytesProvider);
      ref.invalidate(downloadedEpisodesListProvider);
      ref.invalidate(downloadedEpisodesCountProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleared $deleted downloaded audio ${deleted == 1 ? 'file' : 'files'}'),
          ),
        );
      }
    }
  }
}
