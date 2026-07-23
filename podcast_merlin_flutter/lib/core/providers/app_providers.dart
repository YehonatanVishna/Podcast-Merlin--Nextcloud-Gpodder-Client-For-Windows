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

class EpisodesNotifier extends StateNotifier<AsyncValue<List<Episode>>> {
  final DatabaseHelper _db;
  final int? _podcastId;

  EpisodesNotifier(this._db, this._podcastId) : super(const AsyncValue.loading()) {
    loadEpisodes();
  }

  Future<void> loadEpisodes() async {
    state = const AsyncValue.loading();
    try {
      final list = _podcastId != null
          ? await _db.getEpisodesForPodcast(_podcastId)
          : await _db.getAllEpisodes();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final episodesNotifierProvider = StateNotifierProvider.autoDispose
    .family<EpisodesNotifier, AsyncValue<List<Episode>>, int?>((ref, podcastId) {
  return EpisodesNotifier(ref.watch(databaseProvider), podcastId);
});
