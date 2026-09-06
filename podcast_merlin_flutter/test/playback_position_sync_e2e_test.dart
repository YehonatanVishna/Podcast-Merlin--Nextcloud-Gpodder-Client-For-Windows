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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Playback & Position Sync E2E Tests', () {
    late MockGPodderServer mockServer;
    late DatabaseHelper db;
    late TestSecureStorageService storage;
    late SyncService syncService;
    late int podcastId;

    setUp(() async {
      mockServer = MockGPodderServer(
        expectedUsername: 'playeruser',
        expectedPassword: 'playerpassword',
      );
      await mockServer.start();

      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');

      storage = TestSecureStorageService(
        serverUrl: mockServer.baseUrl,
        username: 'playeruser',
        password: 'playerpassword',
      );

      syncService = SyncService(
        apiClient: GPodderApiClient(),
        storage: storage,
        db: db,
      );

      // Insert test podcast and episode into database
      final podcast = Podcast(
        rssUrl: 'https://feeds.example.com/tech_talks.xml',
        title: 'Tech Talks Podcast',
        description: 'Latest tech news',
        imageUrl: 'https://example.com/art.jpg',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      podcastId = await db.insertOrUpdatePodcast(podcast);

      final episode = Episode(
        podcastId: podcastId,
        podcastRss: 'https://feeds.example.com/tech_talks.xml',
        guid: 'tech-ep-101',
        title: 'Episode 101: Flutter & gPodder',
        description: 'Deep dive into gPodder sync',
        mediaUrl: 'https://media.example.com/ep101.mp3',
        publishedAt: DateTime.now(),
        duration: 1800,
        position: 0,
        isPlayed: false,
        imageUrl: 'https://example.com/art.jpg',
      );
      await db.insertEpisodes([episode]);
    });

    tearDown(() async {
      await mockServer.stop();
    });

    test('Playback progress updates position in DB and pushes action to MockGPodderServer', () async {
      final episode = await db.getEpisodeByMediaUrl('https://media.example.com/ep101.mp3');
      expect(episode, isNotNull);

      // Simulate playback progress: 300 seconds into an 1800 second episode
      const currentSec = 300;
      const totalSec = 1800;
      const isPlayed = (totalSec > 0 && currentSec >= (totalSec - 10));

      await db.updateEpisodePlaybackState(episode!.mediaUrl, currentSec, isPlayed: isPlayed);

      final action = GPodderAction(
        podcast: episode.podcastRss,
        episode: episode.mediaUrl,
        action: 'play',
        timestamp: DateTime.now(),
        position: currentSec,
        started: 0,
        total: totalSec,
      );
      await db.enqueueAction(action);
      await syncService.pushPendingActions();

      // Verify SQLite position update
      final updatedEp = await db.getEpisodeByMediaUrl('https://media.example.com/ep101.mp3');
      expect(updatedEp?.position, 300);
      expect(updatedEp?.isPlayed, isFalse);

      // Verify action reached MockGPodderServer
      final storedActions = mockServer.getStoredEpisodeActions();
      expect(storedActions, isNotEmpty);
      final playAction = storedActions.firstWhere((a) => a.episode == 'https://media.example.com/ep101.mp3');
      expect(playAction.position, 300);
      expect(playAction.total, 1800);
      expect(playAction.podcast, 'https://feeds.example.com/tech_talks.xml');
    });

    test('Near-completion playback sets isPlayed true and syncs to server', () async {
      final episode = await db.getEpisodeByMediaUrl('https://media.example.com/ep101.mp3');
      expect(episode, isNotNull);

      // Position near total (1795 out of 1800 -> within 10 seconds of completion)
      const currentSec = 1795;
      const totalSec = 1800;
      const isPlayed = (totalSec > 0 && currentSec >= (totalSec - 10));

      await db.updateEpisodePlaybackState(episode!.mediaUrl, currentSec, isPlayed: isPlayed);

      final action = GPodderAction(
        podcast: episode.podcastRss,
        episode: episode.mediaUrl,
        action: 'play',
        timestamp: DateTime.now(),
        position: currentSec,
        started: 0,
        total: totalSec,
      );
      await db.enqueueAction(action);
      await syncService.pushPendingActions();

      // Verify SQLite reflects completed state
      final completedEp = await db.getEpisodeByMediaUrl('https://media.example.com/ep101.mp3');
      expect(completedEp?.position, 1795);
      expect(completedEp?.isPlayed, isTrue);

      // Verify server received completed play action
      final storedActions = mockServer.getStoredEpisodeActions();
      final lastAction = storedActions.last;
      expect(lastAction.position, 1795);
    });

    test('Remote position updates on MockGPodderServer sync back to local database', () async {
      // Seed remote server with an action setting position to 1250 / 1800
      final remoteAction = GPodderAction(
        podcast: 'https://feeds.example.com/tech_talks.xml',
        episode: 'https://media.example.com/ep101.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 1250,
        started: 0,
        total: 1800,
      );
      mockServer.seedEpisodeActions([remoteAction]);

      // Perform full sync
      final syncSuccess = await syncService.performFullSync();
      expect(syncSuccess, isTrue);

      // Local episode in DB should reflect remote position 1250
      final syncedEp = await db.getEpisodeByMediaUrl('https://media.example.com/ep101.mp3');
      expect(syncedEp?.position, 1250);
    });
  });
}
