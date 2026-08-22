import '../podcasts/rss_feed_parser.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/podcast.dart';
import '../../core/models/sync_status.dart';
import '../../core/services/image_cache_service.dart';
import '../../core/utils/error_formatter.dart';
import 'gpodder_api_client.dart';
import 'secure_storage_service.dart';

typedef SyncProgressCallback = void Function(SyncStage stage, String? detail);

class SyncService {
  final GPodderApiClient _apiClient;
  final SecureStorageService _storage;
  final DatabaseHelper _db;
  final RssFeedParser _rssParser;

  String? lastError;
  List<String> lastFeedWarnings = [];

  SyncService({
    GPodderApiClient? apiClient,
    SecureStorageService? storage,
    DatabaseHelper? db,
    RssFeedParser? rssParser,
  })  : _apiClient = apiClient ?? GPodderApiClient(),
        _storage = storage ?? SecureStorageService(),
        _db = db ?? DatabaseHelper.instance,
        _rssParser = rssParser ?? RssFeedParser();

  /// Full synchronization workflow (Ping server first; if online -> push backlog & pull changes; if offline -> parse existing subscriptions directly)
  Future<bool> performFullSync({SyncProgressCallback? onProgress}) async {
    lastError = null;
    lastFeedWarnings = [];

    final serverUrl = await _storage.read(SecureStorageService.keyServerUrl);
    final username = await _storage.read(SecureStorageService.keyUsername);
    final password = await _storage.read(SecureStorageService.keyPassword);

    if (serverUrl == null || serverUrl.isEmpty ||
        username == null || username.isEmpty ||
        password == null || password.isEmpty) {
      lastError = 'Server credentials not configured. Please enter server URL, username, and password in Settings.';
      return false;
    }

    onProgress?.call(SyncStage.connectingGpodder, 'Pinging gPodder service...');
    final isOnline = await _apiClient.pingServer(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    if (!isOnline) {
      // Offline fallback mode: proceed directly to parse existing local subscriptions via RSS
      onProgress?.call(SyncStage.fetchingFeed, 'gPodder server offline. Refreshing local subscriptions...');
      await _refreshLocalPodcastsDirectly(onProgress);
      return true;
    }

    try {
      // 1. Push pending subscription backlog & pending play actions
      onProgress?.call(SyncStage.pushingActions, 'Pushing local backlog to gPodder...');
      await _pushPendingSubscriptionChanges(serverUrl!, username!, password!);
      final pushedOk = await _pushPendingActions(serverUrl, username, password);
      if (!pushedOk) {
        lastFeedWarnings.add('Failed to push offline playback actions to gPodder server.');
      }

      // 2. Fetch remote subscription changes
      onProgress?.call(SyncStage.fetchingSubscriptions, 'Fetching subscriptions from gPodder...');
      final lastTsRaw = await _storage.read(SecureStorageService.keyLastActionTimestamp) ?? '0';
      final lastTs = int.tryParse(lastTsRaw) ?? 0;

      final localPodcasts = await _db.getAllPodcasts();
      // If local database has 0 podcasts, force sinceTimestamp = 0 to retrieve full subscription list from server
      final fetchSinceTs = localPodcasts.isEmpty ? 0 : lastTs;

      final subResponse = await _apiClient.fetchSubscriptions(
        serverUrl: serverUrl,
        username: username,
        password: password,
        sinceTimestamp: fetchSinceTs,
      );

      if (subResponse == null) {
        lastError = 'Failed to fetch subscriptions: ${_apiClient.lastError ?? "Unable to retrieve subscriptions from server"}';
        return false;
      }

      int? newTimestampToSave;

      final addList = (subResponse['add'] as List?)?.cast<String>() ?? [];
      final removeList = (subResponse['remove'] as List?)?.cast<String>() ?? [];

      // 2a. Handle podcast removals
      for (final rssUrl in removeList) {
        try {
          await _db.deletePodcastByUrl(rssUrl);
        } catch (e) {
          lastFeedWarnings.add('Failed to remove $rssUrl: ${AppErrorFormatter.format(e)}');
        }
      }

      // 2b. Add new remote subscriptions in parallel
      final feedsToAdd = <String>[];
      for (final rssUrl in addList) {
        final existing = await _db.getPodcastByRssUrl(rssUrl);
        if (existing == null || existing.isDead) {
          feedsToAdd.add(rssUrl);
        }
      }

      if (feedsToAdd.isNotEmpty) {
        int addedCount = 0;
        final totalToAdd = feedsToAdd.length;
        onProgress?.call(SyncStage.fetchingFeed, 'Fetching podcast feeds ($addedCount/$totalToAdd)...');

        await _processInParallel<String>(
          items: feedsToAdd,
          worker: (rssUrl) async {
            try {
              await fetchAndSavePodcastFeed(rssUrl);
            } catch (e) {
              final errStr = AppErrorFormatter.format(e);
              final fullErr = '$rssUrl: $errStr';
              lastFeedWarnings.add(fullErr);

              // Store a dead podcast stub in local database so it is saved in subs
              // and future sync cycles do not continuously block timestamp updates
              final stubTitle = _extractTitleFromUrl(rssUrl);
              final deadPod = Podcast(
                rssUrl: rssUrl,
                title: stubTitle,
                imageUrl: '',
                description: 'Feed unavailable ($errStr)',
                link: rssUrl,
                lastUpdated: DateTime.now(),
                isDead: true,
                lastFeedError: errStr,
                feedErrorCount: 1,
              );
              await _db.insertOrUpdatePodcast(deadPod);
            } finally {
              addedCount++;
              onProgress?.call(
                SyncStage.fetchingFeed,
                'Fetching podcast feeds ($addedCount/$totalToAdd)...',
              );
            }
          },
        );
      }

      // 2c. Refresh existing local podcasts not included in add/remove delta in parallel
      final feedsToRefresh = localPodcasts
          .where((pod) => !removeList.contains(pod.rssUrl) && !addList.contains(pod.rssUrl))
          .toList();

      if (feedsToRefresh.isNotEmpty) {
        int refreshedCount = 0;
        final totalToRefresh = feedsToRefresh.length;
        onProgress?.call(SyncStage.fetchingFeed, 'Refreshing podcast feeds ($refreshedCount/$totalToRefresh)...');

        await _processInParallel<Podcast>(
          items: feedsToRefresh,
          worker: (pod) async {
            try {
              await fetchAndSavePodcastFeed(pod.rssUrl);
              await _db.markPodcastHealthy(pod.rssUrl);
            } catch (e) {
              final errStr = AppErrorFormatter.format(e);
              final fullErr = '${pod.title} (${pod.rssUrl}): $errStr';
              lastFeedWarnings.add(fullErr);
              await _db.markPodcastDead(pod.rssUrl, errStr);
            } finally {
              refreshedCount++;
              onProgress?.call(
                SyncStage.fetchingFeed,
                'Refreshing podcast feeds ($refreshedCount/$totalToRefresh)...',
              );
            }
          },
        );
      }

      if (subResponse['timestamp'] != null) {
        newTimestampToSave = (subResponse['timestamp'] as num).toInt();
      }

      // 3. Fetch remote episode actions
      onProgress?.call(SyncStage.fetchingEpisodeActions, 'Syncing episode playback with gPodder...');
      final remoteActions = await _apiClient.fetchEpisodeActions(
        serverUrl: serverUrl,
        username: username,
        password: password,
        sinceTimestamp: fetchSinceTs,
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

      // 4. Save new timestamp
      if (newTimestampToSave != null && newTimestampToSave > 0) {
        await _storage.write(
          SecureStorageService.keyLastActionTimestamp,
          newTimestampToSave.toString(),
        );
      }

      return true;
    } catch (e) {
      lastError = AppErrorFormatter.format(e);
      await _refreshLocalPodcastsDirectly(onProgress);
      return true;
    }
  }

  /// Refreshes all locally stored podcasts directly via RSS feeds in parallel
  Future<void> _refreshLocalPodcastsDirectly(SyncProgressCallback? onProgress) async {
    final localPodcasts = await _db.getAllPodcasts();
    if (localPodcasts.isEmpty) {
      lastFeedWarnings.add('gPodder server is offline and no local podcasts are stored.');
      return;
    }

    lastFeedWarnings.add('gPodder server is offline. Refreshed ${localPodcasts.length} local subscription feeds directly via RSS.');

    int refreshedCount = 0;
    final totalToRefresh = localPodcasts.length;
    onProgress?.call(SyncStage.fetchingFeed, 'Refreshing local feeds ($refreshedCount/$totalToRefresh)...');

    await _processInParallel<Podcast>(
      items: localPodcasts,
      worker: (pod) async {
        try {
          await fetchAndSavePodcastFeed(pod.rssUrl);
          await _db.markPodcastHealthy(pod.rssUrl);
        } catch (e) {
          final errStr = AppErrorFormatter.format(e);
          lastFeedWarnings.add('${pod.title} (${pod.rssUrl}): $errStr');
          await _db.markPodcastDead(pod.rssUrl, errStr);
        } finally {
          refreshedCount++;
          onProgress?.call(
            SyncStage.fetchingFeed,
            'Refreshing local feeds ($refreshedCount/$totalToRefresh)...',
          );
        }
      },
    );
  }

  /// Process items in parallel with a concurrency pool limit
  Future<void> _processInParallel<T>({
    required List<T> items,
    required Future<void> Function(T item) worker,
    int concurrency = 6,
  }) async {
    if (items.isEmpty) return;
    int index = 0;
    final futures = <Future<void>>[];

    Future<void> runWorker() async {
      while (true) {
        final currentIndex = index++;
        if (currentIndex >= items.length) break;
        await worker(items[currentIndex]);
      }
    }

    final poolSize = items.length < concurrency ? items.length : concurrency;
    for (int i = 0; i < poolSize; i++) {
      futures.add(runWorker());
    }
    await Future.wait(futures);
  }

  /// Push both pending subscription changes and pending playback actions to gPodder
  Future<bool> pushPendingBacklog() async {
    final serverUrl = await _storage.read(SecureStorageService.keyServerUrl);
    final username = await _storage.read(SecureStorageService.keyUsername);
    final password = await _storage.read(SecureStorageService.keyPassword);

    if (serverUrl == null || username == null || password == null ||
        serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      return false;
    }

    final isOnline = await _apiClient.pingServer(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    if (!isOnline) {
      return false;
    }

    final subOk = await _pushPendingSubscriptionChanges(serverUrl, username, password);
    final actionOk = await _pushPendingActions(serverUrl, username, password);
    return subOk && actionOk;
  }

  /// Push enqueued subscription add/remove backlog to gPodder server
  Future<bool> _pushPendingSubscriptionChanges(String serverUrl, String username, String password) async {
    final pendingMap = await _db.getPendingSubscriptionChanges();
    final addList = (pendingMap['add'] as List?)?.cast<String>() ?? [];
    final removeList = (pendingMap['remove'] as List?)?.cast<String>() ?? [];
    final maxId = (pendingMap['maxId'] as num?)?.toInt() ?? 0;

    if (addList.isEmpty && removeList.isEmpty) return true;

    final success = await _apiClient.uploadSubscriptionChanges(
      serverUrl: serverUrl,
      username: username,
      password: password,
      addUrls: addList,
      removeUrls: removeList,
    );

    if (success && maxId > 0) {
      await _db.clearSubscriptionChangesUpTo(maxId);
    }
    return success;
  }

  /// Push any pending actions to gPodder server asynchronously
  Future<bool> pushPendingActions() async {
    final serverUrl = await _storage.read(SecureStorageService.keyServerUrl);
    final username = await _storage.read(SecureStorageService.keyUsername);
    final password = await _storage.read(SecureStorageService.keyPassword);

    if (serverUrl == null || username == null || password == null ||
        serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      return false;
    }

    return _pushPendingActions(serverUrl, username, password);
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
    } else {
      lastError = _apiClient.lastError ?? 'Failed to upload episode actions.';
    }
    return success;
  }

  /// Download and parse RSS feed for a podcast URL, then store to database
  Future<Podcast?> fetchAndSavePodcastFeed(
    String rssUrl, {
    SyncProgressCallback? onProgress,
  }) async {
    lastError = null;
    onProgress?.call(SyncStage.fetchingFeed, 'Downloading & parsing RSS feed...');
    
    final RssFeedResult? feedResult;
    try {
      feedResult = await _rssParser.parseFeedFromUrl(rssUrl);
    } catch (e) {
      final err = 'Failed to download or parse RSS feed ($rssUrl): ${AppErrorFormatter.format(e)}';
      lastError = err;
      throw Exception(err);
    }

    if (feedResult == null) {
      final err = 'Failed to parse RSS feed from $rssUrl: empty result';
      lastError = err;
      throw Exception(err);
    }

    onProgress?.call(SyncStage.fetchingFeed, 'Saving podcast: ${feedResult.title}');
    final podcast = Podcast(
      rssUrl: rssUrl,
      title: feedResult.title,
      imageUrl: feedResult.imageUrl,
      description: feedResult.description,
      link: feedResult.link,
      lastUpdated: DateTime.now(),
      isDead: false,
      lastFeedError: null,
      feedErrorCount: 0,
    );

    try {
      final podcastId = await _db.insertOrUpdatePodcast(podcast);
      final savedPod = await _db.getPodcastByRssUrl(rssUrl);

      final episodes = feedResult.episodes.map((ep) {
        return ep.copyWith(
          podcastId: savedPod?.id ?? podcastId,
          podcastRss: rssUrl,
        );
      }).toList();

      await _db.saveEpisodesBatch(episodes);

      // Pre-cache podcast cover and episode image assets on device
      ImageCacheService.precacheImageUrl(feedResult.imageUrl);
      ImageCacheService.precacheBatch(episodes.map((e) => e.imageUrl));

      return savedPod ?? podcast;
    } catch (e) {
      final err = 'Database error saving podcast feed ($rssUrl): ${AppErrorFormatter.format(e)}';
      lastError = err;
      throw Exception(err);
    }
  }

  String _extractTitleFromUrl(String rssUrl) {
    try {
      final uri = Uri.parse(rssUrl);
      final listParam = uri.queryParameters['list'];
      if (listParam != null && listParam.isNotEmpty) {
        return listParam;
      }
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty) {
        return uri.pathSegments.last;
      }
      return uri.host.isNotEmpty ? uri.host : rssUrl;
    } catch (_) {
      return rssUrl;
    }
  }
}
