import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../models/episode.dart';
import '../models/podcast.dart';
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

final audioHandlerProvider = Provider<MerlinAudioHandler>((ref) {
  final handler = MerlinAudioHandler();
  ref.onDispose(() => handler.dispose());
  return handler;
});

class PodcastsNotifier extends StateNotifier<AsyncValue<List<Podcast>>> {
  final DatabaseHelper _db;
  final SyncService _sync;

  PodcastsNotifier(this._db, this._sync) : super(const AsyncValue.loading()) {
    loadPodcasts();
  }

  Future<void> loadPodcasts() async {
    state = const AsyncValue.loading();
    try {
      final list = await _db.getAllPodcasts();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> addPodcastFeed(String rssUrl) async {
    try {
      final saved = await _sync.fetchAndSavePodcastFeed(rssUrl);
      if (saved != null) {
        await loadPodcasts();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> removePodcast(String rssUrl) async {
    try {
      await _db.deletePodcastByUrl(rssUrl);
      await loadPodcasts();
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    try {
      await _sync.performFullSync();
      await loadPodcasts();
    } catch (_) {}
  }
}

final podcastsNotifierProvider =
    StateNotifierProvider<PodcastsNotifier, AsyncValue<List<Podcast>>>((ref) {
  return PodcastsNotifier(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
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
  final int? _podcastId;
  static const int pageSize = 25;

  EpisodesNotifier(this._db, this._podcastId) : super(const EpisodesState(isLoading: true)) {
    loadEpisodes();
  }

  Future<void> loadEpisodes({EpisodeFilter? filter}) async {
    final currentFilter = filter ?? state.filter;
    state = state.copyWith(isLoading: true, error: null, filter: currentFilter);
    try {
      final list = _podcastId != null
          ? await _db.getEpisodesForPodcast(_podcastId!, limit: pageSize, offset: 0, filter: currentFilter)
          : await _db.getAllEpisodes(limit: pageSize, offset: 0, filter: currentFilter);

      state = EpisodesState(
        episodes: list,
        isLoading: false,
        isLoadingMore: false,
        hasMore: list.length >= pageSize,
        filter: currentFilter,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreEpisodes() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final offset = state.episodes.length;
      final newEpisodes = _podcastId != null
          ? await _db.getEpisodesForPodcast(_podcastId!, limit: pageSize, offset: offset, filter: state.filter)
          : await _db.getAllEpisodes(limit: pageSize, offset: offset, filter: state.filter);

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
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> setFilter(EpisodeFilter filter) async {
    if (state.filter == filter && !state.isLoading) return;
    await loadEpisodes(filter: filter);
  }

  Future<void> refresh() async {
    await loadEpisodes();
  }
}

final episodesNotifierProvider = StateNotifierProvider.autoDispose
    .family<EpisodesNotifier, EpisodesState, int?>((ref, podcastId) {
  return EpisodesNotifier(ref.watch(databaseProvider), podcastId);
});

