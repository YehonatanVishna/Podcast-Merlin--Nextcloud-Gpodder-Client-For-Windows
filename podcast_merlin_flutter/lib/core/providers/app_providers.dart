import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../models/episode.dart';
import '../models/podcast.dart';
import '../models/sync_status.dart';
import '../services/image_cache_service.dart';
import '../utils/error_formatter.dart';
import '../../features/player/audio_player_service.dart';
import '../../features/sync/gpodder_api_client.dart';
import '../../features/sync/secure_storage_service.dart';
import '../../features/sync/sync_service.dart';
import '../../features/discovery/multisource_search_service.dart';
import '../../features/discovery/discovery_notifier.dart';
import '../../features/downloads/episode_download_service.dart';

final databaseProvider = Provider<DatabaseHelper>((ref) => DatabaseHelper.instance);
final secureStorageProvider = Provider<SecureStorageService>((ref) => SecureStorageService());
final apiClientProvider = Provider<GPodderApiClient>((ref) => GPodderApiClient());

final episodeDownloadServiceProvider = Provider<EpisodeDownloadService>((ref) {
  final service = EpisodeDownloadService(
    db: ref.watch(databaseProvider),
  );
  service.reconcileOnStartup();
  ref.onDispose(() => service.dispose());
  return service;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    apiClient: ref.watch(apiClientProvider),
    storage: ref.watch(secureStorageProvider),
    db: ref.watch(databaseProvider),
  );
});

class SyncStatusNotifier extends StateNotifier<SyncStatusState> {
  final SyncService _sync;

  SyncStatusNotifier(this._sync) : super(const SyncStatusState());

  void clearError() {
    state = state.copyWith(error: null);
  }

  void clearWarnings() {
    state = state.copyWith(feedWarnings: const []);
  }

  Future<bool> performFullSync({bool forceFullResync = false}) async {
    if (state.isSyncing) return false;
    state = const SyncStatusState(
      isSyncing: true,
      stage: SyncStage.connectingGpodder,
      currentTask: 'Connecting to gPodder...',
      error: null,
      feedWarnings: [],
    );

    try {
      final success = await _sync.performFullSync(
        forceFullResync: forceFullResync,
        onProgress: (stage, detail) {
          state = SyncStatusState(
            isSyncing: true,
            stage: stage,
            currentTask: detail,
          );
        },
      );
      state = SyncStatusState(
        isSyncing: false,
        stage: success ? SyncStage.completed : SyncStage.error,
        currentTask: null,
        error: success ? null : (_sync.lastError ?? 'gPodder sync completed with warnings'),
        feedWarnings: _sync.lastFeedWarnings,
      );
      return success;
    } catch (e) {
      state = SyncStatusState(
        isSyncing: false,
        stage: SyncStage.error,
        error: AppErrorFormatter.format(e),
      );
      return false;
    }
  }

  Future<bool> pushBacklog() async {
    return _sync.pushPendingBacklog();
  }

  Future<Podcast?> fetchAndSaveFeed(String rssUrl) async {
    state = SyncStatusState(
      isSyncing: true,
      stage: SyncStage.fetchingFeed,
      currentTask: 'Downloading & parsing RSS feed...',
      activeFeedUrl: rssUrl,
      error: null,
    );

    try {
      final pod = await _sync.fetchAndSavePodcastFeed(
        rssUrl,
        onProgress: (stage, detail) {
          state = SyncStatusState(
            isSyncing: true,
            stage: stage,
            currentTask: detail,
            activeFeedUrl: rssUrl,
          );
        },
      );
      state = SyncStatusState(
        isSyncing: false,
        stage: pod != null ? SyncStage.completed : SyncStage.error,
        error: pod == null ? (_sync.lastError ?? 'Failed to parse RSS feed from $rssUrl') : null,
      );
      return pod;
    } catch (e) {
      state = SyncStatusState(
        isSyncing: false,
        stage: SyncStage.error,
        error: AppErrorFormatter.format(e),
      );
      return null;
    }
  }
}

final syncStatusNotifierProvider =
    StateNotifierProvider<SyncStatusNotifier, SyncStatusState>((ref) {
  return SyncStatusNotifier(ref.watch(syncServiceProvider));
});

final audioHandlerProvider = Provider<MerlinAudioHandler>((ref) {
  // This provider is overridden in main.dart with the handler returned by
  // AudioService.init(). If you see this error, make sure the ProviderScope
  // in main() includes the audioHandlerProvider override.
  throw UnimplementedError(
    'audioHandlerProvider must be overridden with AudioService.init() result',
  );
});

class PodcastsNotifier extends StateNotifier<AsyncValue<List<Podcast>>> {
  final DatabaseHelper _db;
  final SyncStatusNotifier _syncStatusNotifier;
  StreamSubscription<SyncStatusState>? _syncSub;

  PodcastsNotifier(this._db, this._syncStatusNotifier) : super(const AsyncValue.loading()) {
    loadPodcasts();
    _syncSub = _syncStatusNotifier.stream.listen((syncState) {
      if (!syncState.isSyncing && syncState.stage == SyncStage.completed) {
        loadPodcasts();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> loadPodcasts() async {
    final previousData = state.valueOrNull;
    if (previousData == null) {
      state = const AsyncValue.loading();
    }
    try {
      final list = await _db.getAllPodcasts();
      if (mounted) {
        state = AsyncValue.data(list);
        ImageCacheService.precacheBatch(list.map((p) => p.imageUrl));
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(AppErrorFormatter.format(e), st);
      }
    }
  }

  Future<bool> addPodcastFeed(String rssUrl) async {
    await _db.queueSubscriptionChange('add', rssUrl);
    final saved = await _syncStatusNotifier.fetchAndSaveFeed(rssUrl);
    if (saved != null) {
      await loadPodcasts();
      _syncStatusNotifier.pushBacklog().catchError((_) => false);
      return true;
    }
    return false;
  }

  Future<void> removePodcast(String rssUrl) async {
    try {
      await _db.queueSubscriptionChange('remove', rssUrl);
      await _db.deletePodcastByUrl(rssUrl);
      await loadPodcasts();
      _syncStatusNotifier.pushBacklog().catchError((_) => false);
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error('Failed to unsubscribe podcast: ${AppErrorFormatter.format(e)}', st);
      }
    }
  }

  Future<void> refreshAll({bool forceFullResync = false}) async {
    await _syncStatusNotifier.performFullSync(forceFullResync: forceFullResync);
    await loadPodcasts();
  }
}

final podcastsNotifierProvider =
    StateNotifierProvider<PodcastsNotifier, AsyncValue<List<Podcast>>>((ref) {
  return PodcastsNotifier(
    ref.watch(databaseProvider),
    ref.watch(syncStatusNotifierProvider.notifier),
  );
});

class EpisodesState {
  final List<Episode> episodes;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final EpisodeFilter filter;

  const EpisodesState({
    this.episodes = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.filter = EpisodeFilter.all,
  });

  EpisodesState copyWith({
    List<Episode>? episodes,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    EpisodeFilter? filter,
  }) {
    return EpisodesState(
      episodes: episodes ?? this.episodes,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      filter: filter ?? this.filter,
    );
  }
}

class EpisodesNotifier extends StateNotifier<EpisodesState> {
  final DatabaseHelper _db;
  final SyncStatusNotifier _syncStatusNotifier;
  final MerlinAudioHandler _audioHandler;
  final EpisodeDownloadService? _downloadService;
  final int? _podcastId;
  StreamSubscription<PositionUpdateEvent>? _posSub;
  StreamSubscription<SyncStatusState>? _syncSub;
  StreamSubscription<DownloadTaskEvent>? _downloadSub;
  static const int pageSize = 25;

  EpisodesNotifier(
    this._db,
    this._syncStatusNotifier,
    this._audioHandler,
    this._podcastId, {
    this._downloadService,
  }) : super(const EpisodesState(isLoading: true)) {
    loadEpisodes();
    _posSub = _audioHandler.onPositionUpdated.listen((event) {
      updateEpisodeProgress(event.mediaUrl, event.position, event.isPlayed);
    });
    _syncSub = _syncStatusNotifier.stream.listen((syncState) {
      if (!syncState.isSyncing && syncState.stage == SyncStage.completed) {
        loadEpisodes(silent: true);
      }
    });
    _downloadSub = _downloadService?.onDownloadEvent.listen((event) {
      _handleDownloadEvent(event);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _syncSub?.cancel();
    _downloadSub?.cancel();
    super.dispose();
  }

  void _handleDownloadEvent(DownloadTaskEvent event) {
    if (!mounted || state.episodes.isEmpty) return;
    final index = state.episodes.indexWhere(
      (e) =>
          (e.id != null && e.id == event.episodeId) ||
          (e.mediaUrl.isNotEmpty && e.mediaUrl == event.mediaUrl),
    );
    if (index != -1) {
      final ep = state.episodes[index];
      final updatedList = List<Episode>.from(state.episodes);
      updatedList[index] = ep.copyWith(
        downloadStatus: event.status,
        downloadProgress: event.progress,
        downloadedBytes: event.downloadedBytes,
        totalBytes: event.totalBytes,
        downloadError: event.error,
        clearDownloadError: event.status != DownloadStatus.failed,
        downloadPath: event.downloadPath ?? (event.status == DownloadStatus.none ? null : ep.downloadPath),
      );
      state = state.copyWith(episodes: updatedList);
    } else if ((event.status == DownloadStatus.downloaded || event.status == DownloadStatus.none) && state.filter == EpisodeFilter.downloaded) {
      loadEpisodes(silent: true);
    }
  }

  void updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) {
    if (!mounted || state.episodes.isEmpty) return;
    final index = state.episodes.indexWhere((e) => e.mediaUrl == mediaUrl);
    if (index != -1) {
      final updatedList = List<Episode>.from(state.episodes);
      updatedList[index] = updatedList[index].copyWith(
        position: position,
        isPlayed: isPlayed,
      );
      state = state.copyWith(episodes: updatedList);
    }
  }

  Future<void> loadEpisodes({EpisodeFilter? filter, bool silent = false}) async {
    final currentFilter = filter ?? state.filter;
    if (!silent || state.episodes.isEmpty) {
      state = state.copyWith(isLoading: true, error: null, filter: currentFilter);
    }
    try {
      final podcastId = _podcastId;
      final fetchLimit = state.episodes.length > pageSize ? state.episodes.length : pageSize;
      final list = podcastId != null
          ? await _db.getEpisodesForPodcast(podcastId, limit: fetchLimit, offset: 0, filter: currentFilter)
          : await _db.getAllEpisodes(limit: fetchLimit, offset: 0, filter: currentFilter);

      if (mounted) {
        state = EpisodesState(
          episodes: list,
          isLoading: false,
          isLoadingMore: false,
          hasMore: list.length >= fetchLimit,
          filter: currentFilter,
        );
        ImageCacheService.precacheBatch(list.map((e) => e.imageUrl));
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: AppErrorFormatter.format(e));
      }
    }
  }

  Future<void> loadMoreEpisodes() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final offset = state.episodes.length;
      final podcastId = _podcastId;
      final newEpisodes = podcastId != null
          ? await _db.getEpisodesForPodcast(podcastId, limit: pageSize, offset: offset, filter: state.filter)
          : await _db.getAllEpisodes(limit: pageSize, offset: offset, filter: state.filter);

      if (!mounted) return;

      if (newEpisodes.isEmpty) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
      } else {
        state = state.copyWith(
          episodes: [...state.episodes, ...newEpisodes],
          isLoadingMore: false,
          hasMore: newEpisodes.length >= pageSize,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoadingMore: false, error: 'Failed to load more episodes: ${AppErrorFormatter.format(e)}');
      }
    }
  }

  Future<bool> toggleStar(Episode episode) async {
    int? epId = episode.id;
    if (epId == null) {
      final found = await _db.getEpisodeByGuid(episode.guid);
      epId = found?.id;
    }
    if (epId == null) return false;

    final newStarred = await _db.toggleEpisodeStarred(epId);
    if (mounted) {
      final updatedList = state.episodes.map((e) {
        if (e.id == epId || (e.guid.isNotEmpty && e.guid == episode.guid)) {
          return e.copyWith(isStarred: newStarred);
        }
        return e;
      }).toList();
      state = state.copyWith(episodes: updatedList);
    }
    return newStarred;
  }

  Future<void> setFilter(EpisodeFilter filter) async {
    if (state.filter == filter && !state.isLoading) return;
    await loadEpisodes(filter: filter);
  }

  Future<void> refresh({Podcast? podcast}) async {
    if (podcast != null && podcast.rssUrl.isNotEmpty) {
      await _syncStatusNotifier.fetchAndSaveFeed(podcast.rssUrl);
    } else {
      await _syncStatusNotifier.performFullSync();
    }
    await loadEpisodes();
  }
}

final episodesNotifierProvider = StateNotifierProvider.autoDispose
    .family<EpisodesNotifier, EpisodesState, int?>((ref, podcastId) {
  return EpisodesNotifier(
    ref.watch(databaseProvider),
    ref.watch(syncStatusNotifierProvider.notifier),
    ref.watch(audioHandlerProvider),
    podcastId,
    downloadService: ref.watch(episodeDownloadServiceProvider),
  );
});

final downloadedEpisodesCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final downloadService = ref.watch(episodeDownloadServiceProvider);

  final sub = downloadService.onDownloadEvent.listen((event) {
    if (event.status == DownloadStatus.downloaded || event.status == DownloadStatus.none) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(sub.cancel);

  final downloaded = await db.getDownloadedEpisodes();
  return downloaded.length;
});

final downloadStorageUsageBytesProvider = FutureProvider.autoDispose<int>((ref) async {
  final service = ref.watch(episodeDownloadServiceProvider);

  final sub = service.onDownloadEvent.listen((event) {
    if (event.status == DownloadStatus.downloaded || event.status == DownloadStatus.none) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(sub.cancel);

  return service.getTotalDownloadStorageBytes();
});

final activeDownloadsCountProvider = StreamProvider.autoDispose<int>((ref) async* {
  final service = ref.watch(episodeDownloadServiceProvider);
  yield service.activeAndQueuedCount;
  await for (final _ in service.onDownloadEvent) {
    yield service.activeAndQueuedCount;
  }
});

final downloadTasksStreamProvider =
    StreamProvider.autoDispose<Map<int, DownloadTaskEvent>>((ref) async* {
  final service = ref.watch(episodeDownloadServiceProvider);
  yield service.currentTasks;
  await for (final _ in service.onDownloadEvent) {
    yield service.currentTasks;
  }
});

final downloadedEpisodesListProvider =
    FutureProvider.autoDispose<List<Episode>>((ref) async {
  final db = ref.watch(databaseProvider);
  final service = ref.watch(episodeDownloadServiceProvider);
  final sub = service.onDownloadEvent.listen((event) {
    if (event.status == DownloadStatus.downloaded || event.status == DownloadStatus.none) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(sub.cancel);
  return db.getDownloadedEpisodes();
});

final failedEpisodesListProvider =
    FutureProvider.autoDispose<List<Episode>>((ref) async {
  final db = ref.watch(databaseProvider);
  final service = ref.watch(episodeDownloadServiceProvider);
  final sub = service.onDownloadEvent.listen((event) {
    if (event.status == DownloadStatus.failed ||
        event.status == DownloadStatus.none ||
        event.status == DownloadStatus.downloading ||
        event.status == DownloadStatus.queued) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(sub.cancel);
  return db.getFailedEpisodes();
});

final multisourceSearchServiceProvider = Provider<MultisourceSearchService>((ref) {
  return MultisourceSearchService();
});

final discoveryNotifierProvider =
    StateNotifierProvider<DiscoveryNotifier, DiscoveryState>((ref) {
  return DiscoveryNotifier(ref.watch(multisourceSearchServiceProvider));
});

