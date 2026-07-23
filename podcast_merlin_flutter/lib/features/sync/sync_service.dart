import '../podcasts/rss_feed_parser.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/podcast.dart';
import '../../core/models/sync_status.dart';
import 'gpodder_api_client.dart';
import 'secure_storage_service.dart';

typedef SyncProgressCallback = void Function(SyncStage stage, String? detail);

class SyncService {
  final GPodderApiClient _apiClient;
  final SecureStorageService _storage;
  final DatabaseHelper _db;
  final RssFeedParser _rssParser;

  SyncService({
    GPodderApiClient? apiClient,
    SecureStorageService? storage,
    DatabaseHelper? db,
    RssFeedParser? rssParser,
  })  : _apiClient = apiClient ?? GPodderApiClient(),
        _storage = storage ?? SecureStorageService(),
        _db = db ?? DatabaseHelper.instance,
        _rssParser = rssParser ?? RssFeedParser();

  /// Full synchronization workflow (Pull remote changes, push pending actions, refresh RSS)
  Future<bool> performFullSync({SyncProgressCallback? onProgress}) async {
    final serverUrl = await _storage.read(SecureStorageService.keyServerUrl);
    final username = await _storage.read(SecureStorageService.keyUsername);
    final password = await _storage.read(SecureStorageService.keyPassword);

    if (serverUrl == null || username == null || password == null) {
      return false;
    }

    try {
      // 1. Push pending local actions first (with collapsing)
      onProgress?.call(SyncStage.pushingActions, 'Pushing local actions to gPodder...');
      await _pushPendingActions(serverUrl, username, password);

      // 2. Fetch remote subscription changes
      onProgress?.call(SyncStage.fetchingSubscriptions, 'Fetching subscriptions from gPodder...');
      final lastTsRaw = await _storage.read(SecureStorageService.keyLastActionTimestamp) ?? '0';
      final lastTs = int.tryParse(lastTsRaw) ?? 0;

      final subResponse = await _apiClient.fetchSubscriptions(
        serverUrl: serverUrl,
        username: username,
        password: password,
        sinceTimestamp: lastTs,
      );

      int? newTimestampToSave;

      if (subResponse != null) {
        final addList = (subResponse['add'] as List?)?.cast<String>() ?? [];
        final removeList = (subResponse['remove'] as List?)?.cast<String>() ?? [];

        for (final rssUrl in addList) {
          final existing = await _db.getPodcastByRssUrl(rssUrl);
          if (existing == null) {
            onProgress?.call(SyncStage.fetchingFeed, 'Fetching podcast feed: $rssUrl');
            await fetchAndSavePodcastFeed(rssUrl, onProgress: onProgress);
          }
        }

        for (final rssUrl in removeList) {
          await _db.deletePodcastByUrl(rssUrl);
        }

        if (subResponse['timestamp'] != null) {
          newTimestampToSave = (subResponse['timestamp'] as num).toInt();
        }
      }

      // 3. Fetch remote episode actions
      onProgress?.call(SyncStage.fetchingEpisodeActions, 'Syncing episode playback with gPodder...');
      final remoteActions = await _apiClient.fetchEpisodeActions(
        serverUrl: serverUrl,
        username: username,
        password: password,
        sinceTimestamp: lastTs,
      );

      for (final action in remoteActions) {
        if (action.action == 'play') {
          final isPlayed = (action.total > 0 && action.position >= (action.total - 10)) ||
              (action.total == 0 && action.position > 120);
          await _db.updateEpisodePlaybackState(
            action.episode,
            action.position,
            isPlayed: isPlayed,
          );
        }
      }

      // 4. Save new timestamp ONLY after subscriptions & actions both succeed
      if (newTimestampToSave != null) {
        await _storage.write(
          SecureStorageService.keyLastActionTimestamp,
          newTimestampToSave.toString(),
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pushes enqueued offline actions to server after collapsing duplicates
  Future<bool> _pushPendingActions(String serverUrl, String username, String password) async {
    final pending = await _db.getPendingActions();
    if (pending.isEmpty) return true;

    final collapsed = _db.collapseActions(pending);
    final success = await _apiClient.uploadEpisodeActions(
      serverUrl: serverUrl,
      username: username,
      password: password,
      actions: collapsed,
    );

    if (success) {
      final ids = pending.map((a) => a.id!).where((id) => id > 0).toList();
      await _db.markActionsSynced(ids);
    }
    return success;
  }

  /// Download and parse RSS feed for a podcast URL, then store to database
  Future<Podcast?> fetchAndSavePodcastFeed(
    String rssUrl, {
    SyncProgressCallback? onProgress,
  }) async {
    onProgress?.call(SyncStage.fetchingFeed, 'Downloading & parsing RSS feed...');
    final feedResult = await _rssParser.parseFeedFromUrl(rssUrl);
    if (feedResult == null) return null;

    onProgress?.call(SyncStage.fetchingFeed, 'Saving podcast: ${feedResult.title}');
    final podcast = Podcast(
      rssUrl: rssUrl,
      title: feedResult.title,
      imageUrl: feedResult.imageUrl,
      description: feedResult.description,
      link: feedResult.link,
      lastUpdated: DateTime.now(),
    );

    final podcastId = await _db.insertOrUpdatePodcast(podcast);
    final savedPod = await _db.getPodcastByRssUrl(rssUrl);

    final episodes = feedResult.episodes.map((ep) {
      return ep.copyWith(
        podcastId: savedPod?.id ?? podcastId,
        podcastRss: rssUrl,
      );
    }).toList();

    await _db.saveEpisodesBatch(episodes);
    return savedPod ?? podcast;
  }
}

