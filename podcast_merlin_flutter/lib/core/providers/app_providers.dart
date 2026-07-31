import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../models/episode.dart';
import '../models/podcast.dart';
import '../models/sync_status.dart';
import '../../features/player/audio_player_service.dart';
import '../../features/sync/gpodder_api_client.dart';
import '../../features/sync/secure_storage_service.dart';
import '../../features/sync/sync_service.dart';

final databaseProvider = Provider<DatabaseHelper>((ref) => DatabaseHelper.instance);
final secureStorageProvider = Provider<SecureStorageService>((ref) => SecureStorageService());
final apiClientProvider = Provider<GPodderApiClient>((ref) => GPodderApiClient());

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

  Future<bool> performFullSync() async {
    if (state.isSyncing) return false;
    state = const SyncStatusState(
      isSyncing: true,
      stage: SyncStage.connectingGpodder,
      currentTask: 'Connecting to gPodder...',
    );

    try {
      final success = await _sync.performFullSync(
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
        error: success ? null : 'gPodder sync completed with warnings',
      );
      return success;
    } catch (e) {
      state = SyncStatusState(
        isSyncing: false,
        stage: SyncStage.error,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<Podcast?> fetchAndSaveFeed(String rssUrl) async {
    state = SyncStatusState(
      isSyncing: true,
      stage: SyncStage.fetchingFeed,
      currentTask: 'Downloading & parsing RSS feed...',
      activeFeedUrl: rssUrl,
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
        error: pod == null ? 'Failed to parse RSS feed' : null,
      );
      return pod;
    } catch (e) {
      state = SyncStatusState(
        isSyncing: false,
        stage: SyncStage.error,
        error: e.toString(),
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

  PodcastsNotifier(this._db, this._syncStatusNotifier) : super(const AsyncValue.loading()) {
    loadPodcasts();
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
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<bool> addPodcastFeed(String rssUrl) async {
    final saved = await _syncStatusNotifier.fetchAndSaveFeed(rssUrl);
    if (saved != null) {
      await loadPodcasts();
      return true;
    }
    return false;
  }

  Future<void> removePodcast(String rssUrl) async {
    try {
      await _db.deletePodcastByUrl(rssUrl);
      await loadPodcasts();
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    await _syncStatusNotifier.performFullSync();
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
  final int? _podcastId;
  static const int pageSize = 25;

  EpisodesNotifier(this._db, this._syncStatusNotifier, this._podcastId)
      : super(const EpisodesState(isLoading: true)) {
    loadEpisodes();
  }

  Future<void> loadEpisodes({EpisodeFilter? filter}) async {
    final currentFilter = filter ?? state.filter;
    state = state.copyWith(isLoading: true, error: null, filter: currentFilter);
    try {
      final podcastId = _podcastId;
      final list = podcastId != null
          ? await _db.getEpisodesForPodcast(podcastId, limit: pageSize, offset: 0, filter: currentFilter)
          : await _db.getAllEpisodes(limit: pageSize, offset: 0, filter: currentFilter);

      if (mounted) {
        state = EpisodesState(
          episodes: list,
          isLoading: false,
          isLoadingMore: false,
          hasMore: list.length >= pageSize,
          filter: currentFilter,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  Future<void> loadMoreEpisodes() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
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
        state = state.copyWith(isLoadingMore: false);
      }
    }
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
    podcastId,
  );
});


