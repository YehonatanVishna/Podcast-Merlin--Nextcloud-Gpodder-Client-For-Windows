import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/gpodder_action.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';

import 'mocks/mock_gpodder_server.dart';

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

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseHelper URL Normalization Tests', () {
    test('normalizeUrl handles protocols, trailing slashes, and query params', () {
      expect(
        DatabaseHelper.normalizeUrl('https://example.com/audio/ep1.mp3?tracking=1&user=42'),
        equals('example.com/audio/ep1.mp3'),
      );
      expect(
        DatabaseHelper.normalizeUrl('http://EXAMPLE.COM/audio/ep1.mp3/'),
        equals('example.com/audio/ep1.mp3'),
      );
      expect(
        DatabaseHelper.normalizeUrl('https://example.com/audio/ep1%20track.mp3#t=10'),
        equals('example.com/audio/ep1 track.mp3'),
      );
    });
  });

  group('DatabaseHelper Remote Action Matching Tests', () {
    late DatabaseHelper db;
    late int podcastId;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');

      final podcast = Podcast(
        rssUrl: 'https://feeds.example.com/show1.xml',
        title: 'Show 1',
        description: 'Test Show',
        imageUrl: 'https://example.com/art.jpg',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      podcastId = await db.insertOrUpdatePodcast(podcast);

      final episodes = [
        Episode(
          podcastId: podcastId,
          podcastRss: 'https://feeds.example.com/show1.xml',
          guid: 'guid-ep-1',
          title: 'Ep 1',
          description: 'Desc 1',
          mediaUrl: 'https://cdn.example.com/episodes/ep1.mp3',
          duration: 3600,
          position: 0,
          isPlayed: false,
          imageUrl: 'https://example.com/art.jpg',
        ),
        Episode(
          podcastId: podcastId,
          podcastRss: 'https://feeds.example.com/show1.xml',
          guid: 'guid-ep-2',
          title: 'Ep 2',
          description: 'Desc 2',
          mediaUrl: 'https://cdn.example.com/episodes/ep2.mp3?tracking=rss',
          duration: 1800,
          position: 0,
          isPlayed: false,
          imageUrl: 'https://example.com/art.jpg',
        ),
        Episode(
          podcastId: podcastId,
          podcastRss: 'https://feeds.example.com/show1.xml',
          guid: 'guid-ep-3',
          title: 'Ep 3',
          description: 'Desc 3',
          mediaUrl: 'https://cdn.example.com/episodes/ep3.mp3',
          duration: 600,
          position: 0,
          isPlayed: false,
          imageUrl: 'https://example.com/art.jpg',
        ),
      ];
      await db.insertEpisodes(episodes);
    });

    test('matches remote action by guid even if mediaUrl differs due to redirect tracker', () async {
      final actions = [
        GPodderAction(
          podcast: 'https://feeds.example.com/show1.xml',
          episode: 'https://dts.podtrac.com/redirect.mp3/cdn.example.com/episodes/ep1.mp3',
          guid: 'guid-ep-1',
          action: 'play',
          timestamp: DateTime.now(),
          position: 1250,
          started: 0,
          total: 3600,
        ),
      ];

      await db.applyRemoteEpisodeActions(actions);

      final updated = await db.getEpisodeByGuid('guid-ep-1');
      expect(updated, isNotNull);
      expect(updated!.position, equals(1250));
      expect(updated.isPlayed, isFalse);
    });

    test('matches remote action by normalized URL when protocols or query params differ', () async {
      final actions = [
        GPodderAction(
          podcast: 'https://feeds.example.com/show1.xml',
          episode: 'http://cdn.example.com/episodes/ep2.mp3?different_param=xyz',
          guid: null,
          action: 'play',
          timestamp: DateTime.now(),
          position: 900,
          started: 0,
          total: 1800,
        ),
      ];

      await db.applyRemoteEpisodeActions(actions);

      final updated = await db.getEpisodeByGuid('guid-ep-2');
      expect(updated, isNotNull);
      expect(updated!.position, equals(900));
      expect(updated.isPlayed, isFalse);
    });

    test('correctly marks episode as played using DB duration when action.total <= 0', () async {
      // AntennaPod or gpoddersync often sends position=duration and total=0 or total=-1
      final actions = [
        GPodderAction(
          podcast: 'https://feeds.example.com/show1.xml',
          episode: 'https://cdn.example.com/episodes/ep3.mp3',
          guid: 'guid-ep-3',
          action: 'play',
          timestamp: DateTime.now(),
          position: 595, // 595 >= (600 - 15) -> completed
          started: 0,
          total: 0, // total missing from server action
        ),
      ];

      await db.applyRemoteEpisodeActions(actions);

      final updated = await db.getEpisodeByGuid('guid-ep-3');
      expect(updated, isNotNull);
      expect(updated!.position, equals(595));
      expect(updated.isPlayed, isTrue);
    });

    test('chronologically sorts multiple actions so latest action determines final position', () async {
      final earlier = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final later = DateTime.fromMillisecondsSinceEpoch(1700001000000);

      // Pass out-of-order actions: later first, then earlier
      final actions = [
        GPodderAction(
          podcast: 'https://feeds.example.com/show1.xml',
          episode: 'https://cdn.example.com/episodes/ep1.mp3',
          guid: 'guid-ep-1',
          action: 'play',
          timestamp: later,
          position: 2500,
          started: 0,
          total: 3600,
        ),
        GPodderAction(
          podcast: 'https://feeds.example.com/show1.xml',
          episode: 'https://cdn.example.com/episodes/ep1.mp3',
          guid: 'guid-ep-1',
          action: 'play',
          timestamp: earlier,
          position: 300,
          started: 0,
          total: 3600,
        ),
      ];

      await db.applyRemoteEpisodeActions(actions);

      final updated = await db.getEpisodeByGuid('guid-ep-1');
      expect(updated, isNotNull);
      // The later timestamp position should win
      expect(updated!.position, equals(2500));
    });
  });

  group('SyncService First Sync & Force Full Resync E2E', () {
    late MockGPodderServer mockServer;
    late DatabaseHelper db;
    late TestSecureStorageService storage;
    late SyncService syncService;

    setUp(() async {
      mockServer = MockGPodderServer(
        expectedUsername: 'syncuser',
        expectedPassword: 'syncpassword',
      );
      await mockServer.start();

      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');

      storage = TestSecureStorageService(
        serverUrl: mockServer.baseUrl,
        username: 'syncuser',
        password: 'syncpassword',
      );

      syncService = SyncService(
        apiClient: GPodderApiClient(),
        storage: storage,
        db: db,
      );
    });

    tearDown(() async {
      await mockServer.stop();
    });

    test('first sync fetches all episode actions from timestamp 0 and applies them', () async {
      // 1. Insert local podcast and episode
      final podcast = Podcast(
        rssUrl: 'https://feeds.example.com/first_sync_show.xml',
        title: 'First Sync Show',
        description: 'Test',
        imageUrl: 'https://example.com/art.jpg',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: podcast.rssUrl,
        guid: 'ep-sync-first-1',
        title: 'First Ep',
        description: 'First',
        mediaUrl: 'https://media.example.com/ep1.mp3',
        duration: 2000,
        position: 0,
        isPlayed: false,
        imageUrl: 'https://example.com/art.jpg',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: podcast.rssUrl,
        guid: 'ep-sync-first-2',
        title: 'Second Ep',
        description: 'Second',
        mediaUrl: 'https://media.example.com/ep2.mp3',
        duration: 2000,
        position: 0,
        isPlayed: false,
        imageUrl: 'https://example.com/art.jpg',
      );
      await db.insertEpisodes([ep1, ep2]);

      // 2. Mock server has an episode action with GUID and played position
      mockServer.seedEpisodeActions([
        GPodderAction(
          podcast: podcast.rssUrl,
          episode: 'https://media.example.com/ep1.mp3',
          guid: 'ep-sync-first-1',
          action: 'play',
          timestamp: DateTime.now(),
          position: 1200,
          started: 0,
          total: 2000,
        ),
        GPodderAction(
          podcast: podcast.rssUrl,
          episode: 'https://media.example.com/ep2.mp3',
          guid: 'ep-sync-first-2',
          action: 'play',
          timestamp: DateTime.now(),
          position: 1995, // 1995 >= 2000 - 15 -> played!
          started: 0,
          total: 2000,
        ),
      ]);

      // Verify no action timestamp exists initially (first sync)
      final initialActionTs = await storage.read(SecureStorageService.keyLastActionTimestamp);
      expect(initialActionTs, isNull);

      // 3. Perform sync
      final success = await syncService.performFullSync();
      expect(success, isTrue);

      // 4. Verify ep1 position is 1200 and not played
      final updated1 = await db.getEpisodeByGuid('ep-sync-first-1');
      expect(updated1, isNotNull);
      expect(updated1!.position, equals(1200));
      expect(updated1.isPlayed, isFalse);

      // Verify ep2 position is 1995 and marked played
      final updated2 = await db.getEpisodeByGuid('ep-sync-first-2');
      expect(updated2, isNotNull);
      expect(updated2!.position, equals(1995));
      expect(updated2.isPlayed, isTrue);

      // 5. Verify action timestamp is saved
      final savedActionTs = await storage.read(SecureStorageService.keyLastActionTimestamp);
      expect(savedActionTs, isNotNull);
      expect(int.parse(savedActionTs!), greaterThan(0));
    });

    test('forceFullResync: true forces fetching from timestamp 0 even if timestamps were stored', () async {
      // 1. Insert local podcast and episode
      final podcast = Podcast(
        rssUrl: 'https://feeds.example.com/resync_show.xml',
        title: 'Resync Show',
        description: 'Test',
        imageUrl: 'https://example.com/art.jpg',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: podcast.rssUrl,
        guid: 'ep-resync-1',
        title: 'Resync Ep',
        description: 'Desc',
        mediaUrl: 'https://media.example.com/resync_ep1.mp3',
        duration: 1000,
        position: 0,
        isPlayed: false,
        imageUrl: 'https://example.com/art.jpg',
      );
      await db.insertEpisodes([ep1]);

      // Populate mock server with past action
      mockServer.seedEpisodeActions([
        GPodderAction(
          podcast: podcast.rssUrl,
          episode: 'https://media.example.com/resync_ep1.mp3',
          guid: 'ep-resync-1',
          action: 'play',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1600000000000),
          position: 750,
          started: 0,
          total: 1000,
        ),
      ]);

      // Set a future action timestamp in storage to simulate already being up to date
      await storage.write(SecureStorageService.keyLastActionTimestamp, '1700000000');
      await storage.write(SecureStorageService.keyLastSubscriptionTimestamp, '1700000000');

      // Regular sync would pass since=1700000000 and NOT get the old action
      // With forceFullResync: true, it must fetch from 0 and update the position
      final success = await syncService.performFullSync(forceFullResync: true);
      expect(success, isTrue);

      final updated = await db.getEpisodeByGuid('ep-resync-1');
      expect(updated, isNotNull);
      expect(updated!.position, equals(750));
    });

    test('automatic recovery: forces since=0 when local database has 0 playback progress even without forceFullResync', () async {
      final podcast = Podcast(
        rssUrl: 'https://feeds.example.com/recovery_show.xml',
        title: 'Recovery Show',
        description: 'Test',
        imageUrl: 'https://example.com/art.jpg',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep = Episode(
        podcastId: podId,
        podcastRss: podcast.rssUrl,
        guid: 'ep-recovery-1',
        title: 'Recovery Ep',
        description: 'Desc',
        mediaUrl: 'https://media.example.com/recovery_ep1.mp3',
        duration: 2000,
        position: 0,
        isPlayed: false,
        imageUrl: 'https://example.com/art.jpg',
      );
      await db.insertEpisodes([ep]);

      // Past action on server
      mockServer.seedEpisodeActions([
        GPodderAction(
          podcast: podcast.rssUrl,
          episode: 'https://media.example.com/recovery_ep1.mp3',
          guid: 'ep-recovery-1',
          action: 'play',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1650000000000),
          position: 1450,
          started: 0,
          total: 2000,
        ),
      ]);

      // Simulate a scenario where a previous sync stored a timestamp but failed to apply playback
      await storage.write(SecureStorageService.keyLastActionTimestamp, '1700000000');
      await storage.write(SecureStorageService.keyLastSubscriptionTimestamp, '1700000000');

      // Regular performFullSync (forceFullResync: false) must automatically detect no playback
      // and query since: 0
      final success = await syncService.performFullSync(forceFullResync: false);
      expect(success, isTrue);

      final updated = await db.getEpisodeByGuid('ep-recovery-1');
      expect(updated, isNotNull);
      expect(updated!.position, equals(1450));
    });

    test('GPodderAction.fromMap safely parses PHP/MySQL stringified numbers and actions', () {
      final map = {
        'podcast': 'https://feeds.example.com/test.xml',
        'episode': 'https://cdn.example.com/test.mp3',
        'guid': 'test-guid',
        'action': 'pause',
        'timestamp': '1700000000',
        'position': '1850',
        'started': '100',
        'total': '3600',
      };
      final action = GPodderAction.fromMap(map);
      expect(action.position, equals(1850));
      expect(action.started, equals(100));
      expect(action.total, equals(3600));
      expect(action.action, equals('pause'));
      expect(action.timestamp.millisecondsSinceEpoch, equals(1700000000000));
    });

    test('matches remote action by audio filename even across different CDN domains and tracking wrappers', () async {
      final podcast = Podcast(
        rssUrl: 'https://feeds.example.com/fn_show.xml',
        title: 'Filename Show',
        description: 'Test',
        imageUrl: 'https://example.com/art.jpg',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep = Episode(
        podcastId: podId,
        podcastRss: podcast.rssUrl,
        guid: 'unique-fn-guid',
        title: 'Filename Ep',
        description: 'Desc',
        mediaUrl: 'https://cdn.mysite.com/audio/my_awesome_podcast_ep42.mp3?token=secret123',
        duration: 1500,
        position: 0,
        isPlayed: false,
        imageUrl: 'https://example.com/art.jpg',
      );
      await db.insertEpisodes([ep]);

      final actions = [
        GPodderAction(
          podcast: podcast.rssUrl,
          // Completely different host, tracking prefix, and parameters, but identical filename
          episode: 'https://dts.podtrac.com/redirect.mp3/different-host.org/download/my_awesome_podcast_ep42.mp3?aw_param=456',
          guid: null,
          action: 'play',
          timestamp: DateTime.now(),
          position: 1100,
          started: 0,
          total: 1500,
        ),
      ];

      await db.applyRemoteEpisodeActions(actions);

      final updated = await db.getEpisodeByGuid('unique-fn-guid');
      expect(updated, isNotNull);
      expect(updated!.position, equals(1100));
    });
  });
}
