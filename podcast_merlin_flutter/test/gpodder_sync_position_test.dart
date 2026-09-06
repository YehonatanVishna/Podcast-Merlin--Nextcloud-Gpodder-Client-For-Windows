import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/gpodder_action.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';

class MockGPodderApiClient extends GPodderApiClient {
  final List<GPodderAction> uploadedActions = [];
  bool shouldSucceed = true;

  @override
  Future<bool> uploadEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    required List<GPodderAction> actions,
  }) async {
    if (!shouldSucceed) return false;
    uploadedActions.addAll(actions);
    return true;
  }
}

class MockSecureStorageService extends SecureStorageService {
  final Map<String, String> _storage = {
    SecureStorageService.keyServerUrl: 'https://example.com/gpodder',
    SecureStorageService.keyUsername: 'testuser',
    SecureStorageService.keyPassword: 'testpassword',
  };

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async {
    _storage[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('GPodder Action Serialization Tests', () {
    test('toApiJson formats timestamp as ISO 8601 string and includes required fields', () {
      final now = DateTime.utc(2026, 7, 25, 22, 0, 0);
      final action = GPodderAction(
        podcast: 'https://example.com/podcast.xml',
        episode: 'https://example.com/ep1.mp3',
        action: 'play',
        timestamp: now,
        position: 150,
        started: 0,
        total: 1800,
        device: 'podcast_merlin_flutter',
      );

      final json = action.toApiJson();

      expect(json['podcast'], 'https://example.com/podcast.xml');
      expect(json['episode'], 'https://example.com/ep1.mp3');
      expect(json['action'], 'play');
      expect(json['timestamp'], '2026-07-25T22:00:00');
      expect(json['position'], 150);
      expect(json['started'], 0);
      expect(json['total'], 1800);
      expect(json['device'], 'podcast_merlin_flutter');
    });
  });

  group('DatabaseHelper Podcast & Episode Join Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    test('Episode queries join podcasts table and populate podcastRss correctly', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/rss.xml',
        title: 'Test Podcast',
        description: 'Description',
        imageUrl: 'https://example.com/image.png',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );

      final podcastId = await db.insertOrUpdatePodcast(podcast);
      expect(podcastId, greaterThan(0));

      final episode = Episode(
        podcastId: podcastId,
        podcastRss: '', // Initially empty when raw inserted
        guid: 'ep-guid-1',
        title: 'Test Episode 1',
        description: 'Ep Description',
        mediaUrl: 'https://example.com/audio1.mp3',
        publishedAt: DateTime.now(),
        duration: 600,
        position: 120,
        isPlayed: false,
        imageUrl: '',
      );

      await db.insertEpisodes([episode]);

      // 1. Test getEpisodesForPodcast
      final podcastEpisodes = await db.getEpisodesForPodcast(podcastId);
      expect(podcastEpisodes.length, 1);
      expect(podcastEpisodes.first.podcastRss, 'https://example.com/rss.xml');

      // 2. Test getAllEpisodes
      final allEpisodes = await db.getAllEpisodes();
      expect(allEpisodes.length, 1);
      expect(allEpisodes.first.podcastRss, 'https://example.com/rss.xml');

      // 3. Test getAllUnplayedEpisodes
      final unplayedEpisodes = await db.getAllUnplayedEpisodes();
      expect(unplayedEpisodes.length, 1);
      expect(unplayedEpisodes.first.podcastRss, 'https://example.com/rss.xml');

      // 4. Test getEpisodeByMediaUrl
      final epByUrl = await db.getEpisodeByMediaUrl('https://example.com/audio1.mp3');
      expect(epByUrl, isNotNull);
      expect(epByUrl!.podcastRss, 'https://example.com/rss.xml');

      // 5. Test getPodcastById
      final fetchedPod = await db.getPodcastById(podcastId);
      expect(fetchedPod, isNotNull);
      expect(fetchedPod!.rssUrl, 'https://example.com/rss.xml');
    });
  });

  group('SyncService pushPendingActions Tests', () {
    late DatabaseHelper db;
    late MockGPodderApiClient mockApi;
    late MockSecureStorageService mockStorage;
    late SyncService syncService;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');

      mockApi = MockGPodderApiClient();
      mockStorage = MockSecureStorageService();
      syncService = SyncService(
        apiClient: mockApi,
        storage: mockStorage,
        db: db,
      );
    });

    test('pushPendingActions uploads enqueued actions with valid podcast URL and marks them synced', () async {
      final action = GPodderAction(
        podcast: 'https://example.com/podcast.xml',
        episode: 'https://example.com/ep1.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 300,
        started: 0,
        total: 1200,
      );

      await db.enqueueAction(action);

      final pendingBefore = await db.getPendingActions();
      expect(pendingBefore.length, 1);
      expect(pendingBefore.first.podcast, 'https://example.com/podcast.xml');

      final success = await syncService.pushPendingActions();
      expect(success, isTrue);

      expect(mockApi.uploadedActions.length, 1);
      expect(mockApi.uploadedActions.first.podcast, 'https://example.com/podcast.xml');
      expect(mockApi.uploadedActions.first.position, 300);

      final pendingAfter = await db.getPendingActions();
      expect(pendingAfter.isEmpty, isTrue);
    });
  });
}
