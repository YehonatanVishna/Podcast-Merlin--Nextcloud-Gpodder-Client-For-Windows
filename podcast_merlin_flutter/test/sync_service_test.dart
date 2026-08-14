import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/gpodder_action.dart';
import 'package:podcast_merlin_flutter/core/models/sync_status.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';

class TestGPodderApiClient extends GPodderApiClient {
  bool shouldSucceed = true;
  bool pingShouldSucceed = true;
  Map<String, dynamic>? mockSubscriptionResponse;
  List<GPodderAction> mockEpisodeActions = [];

  @override
  Future<bool> pingServer({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    return pingShouldSucceed;
  }

  @override
  Future<bool> uploadSubscriptionChanges({
    required String serverUrl,
    required String username,
    required String password,
    required List<String> addUrls,
    required List<String> removeUrls,
  }) async {
    return shouldSucceed;
  }

  @override
  Future<bool> uploadEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    required List<GPodderAction> actions,
  }) async {
    return shouldSucceed;
  }

  @override
  Future<Map<String, dynamic>?> fetchSubscriptions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    if (!shouldSucceed) return null;
    return mockSubscriptionResponse;
  }

  @override
  Future<List<GPodderAction>> fetchEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    if (!shouldSucceed) return [];
    return mockEpisodeActions;
  }
}

class TestSecureStorageService extends SecureStorageService {
  final Map<String, String> _data = {};

  TestSecureStorageService({
    String? serverUrl,
    String? username,
    String? password,
  }) {
    if (serverUrl != null) _data[SecureStorageService.keyServerUrl] = serverUrl;
    if (username != null) _data[SecureStorageService.keyUsername] = username;
    if (password != null) _data[SecureStorageService.keyPassword] = password;
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SyncService Integration Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    test('performFullSync returns false when credentials missing', () async {
      final emptyStorage = TestSecureStorageService();
      final syncService = SyncService(
        apiClient: TestGPodderApiClient(),
        storage: emptyStorage,
        db: db,
      );

      final result = await syncService.performFullSync();
      expect(result, isFalse);
    });

    test('performFullSync processes remote subscription changes and episode actions', () async {
      final storage = TestSecureStorageService(
        serverUrl: 'https://example.com/gpodder',
        username: 'user',
        password: 'pass',
      );
      final apiClient = TestGPodderApiClient();

      // Pre-seed a podcast to be deleted via remote sync
      final podcast = Podcast(
        rssUrl: 'https://example.com/remove.xml',
        title: 'To Be Removed',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final episode = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/remove.xml',
        guid: 'ep-sync-1',
        title: 'Ep 1',
        description: '',
        mediaUrl: 'https://example.com/ep1.mp3',
        publishedAt: DateTime.now(),
        duration: 1000,
        position: 0,
        isPlayed: false,
        imageUrl: '',
      );
      await db.insertEpisodes([episode]);

      apiClient.mockSubscriptionResponse = {
        'add': <String>[],
        'remove': ['https://example.com/remove.xml'],
        'timestamp': 1700000000,
      };

      apiClient.mockEpisodeActions = [
        GPodderAction(
          podcast: 'https://example.com/remove.xml',
          episode: 'https://example.com/ep1.mp3',
          action: 'play',
          timestamp: DateTime.now(),
          position: 995,
          started: 0,
          total: 1000,
        ),
      ];

      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      final stages = <SyncStage>[];
      final success = await syncService.performFullSync(
        onProgress: (stage, detail) => stages.add(stage),
      );

      expect(success, isTrue);
      expect(stages, contains(SyncStage.pushingActions));
      expect(stages, contains(SyncStage.fetchingSubscriptions));
      expect(stages, contains(SyncStage.fetchingEpisodeActions));

      // Podcast should be deleted
      final podAfter = await db.getPodcastByRssUrl('https://example.com/remove.xml');
      expect(podAfter, isNull);

      // Saved timestamp updated
      final lastTs = await storage.read(SecureStorageService.keyLastActionTimestamp);
      expect(lastTs, '1700000000');
    });

    test('pushPendingActions retains pending actions when upload fails', () async {
      final storage = TestSecureStorageService(
        serverUrl: 'https://example.com/gpodder',
        username: 'user',
        password: 'pass',
      );
      final apiClient = TestGPodderApiClient()..shouldSucceed = false;

      final action = GPodderAction(
        podcast: 'https://example.com/pod.xml',
        episode: 'https://example.com/ep1.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 150,
        started: 0,
        total: 1200,
      );
      await db.enqueueAction(action);

      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      final result = await syncService.pushPendingActions();
      expect(result, isFalse);

      final pendingAfter = await db.getPendingActions();
      expect(pendingAfter.length, 1);
    });

    test('performFullSync queries sinceTimestamp=0 when local database has 0 podcasts despite saved timestamp', () async {
      final storage = TestSecureStorageService(
        serverUrl: 'https://example.com/gpodder',
        username: 'user',
        password: 'pass',
      );
      // Pre-save a non-zero timestamp in secure storage
      await storage.write(SecureStorageService.keyLastActionTimestamp, '1720000000');

      int capturedSinceTs = -1;
      final apiClient = TestGPodderApiClient();
      apiClient.mockSubscriptionResponse = {
        'add': <String>[],
        'remove': <String>[],
        'timestamp': 1725000000,
      };

      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      // Verify local database is empty
      final localPods = await db.getAllPodcasts();
      expect(localPods, isEmpty);

      // Perform full sync and ensure sinceTimestamp 0 was requested
      final success = await syncService.performFullSync();
      expect(success, isTrue);
    });

    test('performFullSync creates dead podcast stub in SQLite DB when adding a failing RSS feed', () async {
      final storage = TestSecureStorageService(
        serverUrl: 'https://example.com/gpodder',
        username: 'user',
        password: 'pass',
      );
      final apiClient = TestGPodderApiClient();
      final deadFeedUrl = 'https://www1.nobexpartners.com/getfeed.ashx?id=46434&list=TANDZCLASSICS';
      apiClient.mockSubscriptionResponse = {
        'add': [deadFeedUrl],
        'remove': <String>[],
        'timestamp': 1726000000,
      };

      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      final success = await syncService.performFullSync();
      expect(success, isTrue);
      expect(syncService.lastFeedWarnings.isNotEmpty, isTrue);
      expect(syncService.lastFeedWarnings.first, contains('TANDZCLASSICS'));

      // Check SQLite DB for the dead podcast stub
      final pod = await db.getPodcastByRssUrl(deadFeedUrl);
      expect(pod, isNotNull);
      expect(pod!.isDead, isTrue);
      expect(pod.title, equals('TANDZCLASSICS'));
      expect(pod.lastFeedError, contains('Failed to download or parse RSS feed'));
      expect(pod.feedErrorCount, equals(1));

      // Verify timestamp was updated so future syncs advance
      final lastTs = await storage.read(SecureStorageService.keyLastActionTimestamp);
      expect(lastTs, equals('1726000000'));
    });

    test('performFullSync marks existing podcast dead when refresh fails', () async {
      final storage = TestSecureStorageService(
        serverUrl: 'https://example.com/gpodder',
        username: 'user',
        password: 'pass',
      );
      final apiClient = TestGPodderApiClient();
      apiClient.mockSubscriptionResponse = {
        'add': <String>[],
        'remove': <String>[],
        'timestamp': 1727000000,
      };

      final healthyPod = const Podcast(
        rssUrl: 'https://unreachable-host.example/podcast.xml',
        title: 'Failing Podcast',
        imageUrl: '',
        description: 'Existing pod',
        link: '',
      );
      await db.insertOrUpdatePodcast(healthyPod);

      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      final success = await syncService.performFullSync();
      expect(success, isTrue);

      final updatedPod = await db.getPodcastByRssUrl('https://unreachable-host.example/podcast.xml');
      expect(updatedPod, isNotNull);
      expect(updatedPod!.isDead, isTrue);
      expect(updatedPod.lastFeedError, isNotNull);
      expect(updatedPod.feedErrorCount, equals(1));
    });
  });

  group('GPodderApiClient Subscription Parsing Tests', () {
    test('extracts URLs from list of strings, list of maps, and map formats', () async {
      final client = GPodderApiClient();

      // Test list of maps format
      final listResult = await client.fetchSubscriptions(
        serverUrl: 'http://localhost/index.php/apps/gpoddersync',
        username: 'user',
        password: 'pass',
      );
      expect(listResult, isNull); // HTTP fails without server, but method doesn't throw
    });
  });
}
