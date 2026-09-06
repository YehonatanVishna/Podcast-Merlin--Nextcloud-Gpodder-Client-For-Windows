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

  group('gPodder API & Protocol E2E Tests (Real HTTP over Mock Server)', () {
    late MockGPodderServer mockServer;
    late GPodderApiClient apiClient;

    setUp(() async {
      mockServer = MockGPodderServer(
        expectedUsername: 'admin',
        expectedPassword: 'secretpassword',
      );
      await mockServer.start();
      apiClient = GPodderApiClient();
    });

    tearDown(() async {
      await mockServer.stop();
    });

    test('checkConnection verifies valid and invalid Basic Auth credentials', () async {
      // Valid credentials
      final valid = await apiClient.checkConnection(
        serverUrl: mockServer.baseUrl,
        username: 'admin',
        password: 'secretpassword',
      );
      expect(valid, isTrue);

      // Invalid credentials
      final invalid = await apiClient.checkConnection(
        serverUrl: mockServer.baseUrl,
        username: 'admin',
        password: 'wrongpassword',
      );
      expect(invalid, isFalse);
    });

    test('fetchSubscriptions and uploadSubscriptionChanges sync deltas', () async {
      mockServer.seedSubscriptions(add: [
        'https://feeds.example.com/podcast1.xml',
        'https://feeds.example.com/podcast2.xml',
      ]);

      // Fetch initial subscriptions (since=0)
      final initialSubs = await apiClient.fetchSubscriptions(
        serverUrl: mockServer.baseUrl,
        username: 'admin',
        password: 'secretpassword',
        sinceTimestamp: 0,
      );

      expect(initialSubs, isNotNull);
      expect(initialSubs!['add'], contains('https://feeds.example.com/podcast1.xml'));
      expect(initialSubs['add'], contains('https://feeds.example.com/podcast2.xml'));
      expect(initialSubs['remove'], isEmpty);

      // Upload changes: add 1, remove 1
      final uploadSuccess = await apiClient.uploadSubscriptionChanges(
        serverUrl: mockServer.baseUrl,
        username: 'admin',
        password: 'secretpassword',
        addUrls: ['https://feeds.example.com/podcast3.xml'],
        removeUrls: ['https://feeds.example.com/podcast1.xml'],
      );
      expect(uploadSuccess, isTrue);

      // Verify server state
      final currentStored = mockServer.getStoredSubscriptions();
      expect(currentStored, contains('https://feeds.example.com/podcast2.xml'));
      expect(currentStored, contains('https://feeds.example.com/podcast3.xml'));
      expect(currentStored, isNot(contains('https://feeds.example.com/podcast1.xml')));
    });

    test('fetchEpisodeActions and uploadEpisodeActions sync playback progress', () async {
      final action1 = GPodderAction(
        podcast: 'https://feeds.example.com/podcast1.xml',
        episode: 'https://media.example.com/ep1.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 450,
        started: 0,
        total: 1800,
      );

      final uploadOk = await apiClient.uploadEpisodeActions(
        serverUrl: mockServer.baseUrl,
        username: 'admin',
        password: 'secretpassword',
        actions: [action1],
      );
      expect(uploadOk, isTrue);

      final remoteActions = await apiClient.fetchEpisodeActions(
        serverUrl: mockServer.baseUrl,
        username: 'admin',
        password: 'secretpassword',
        sinceTimestamp: 0,
      );

      expect(remoteActions.length, 1);
      expect(remoteActions.first.podcast, 'https://feeds.example.com/podcast1.xml');
      expect(remoteActions.first.episode, 'https://media.example.com/ep1.mp3');
      expect(remoteActions.first.position, 450);
      expect(remoteActions.first.total, 1800);
    });
  });

  group('Full SyncService E2E Integration with SQLite & Mock Server', () {
    late MockGPodderServer mockServer;
    late DatabaseHelper db;

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
    });

    tearDown(() async {
      await mockServer.stop();
    });

    test('performFullSync pushes local offline actions and pulls remote state', () async {
      final storage = TestSecureStorageService(
        serverUrl: mockServer.baseUrl,
        username: 'syncuser',
        password: 'syncpassword',
      );

      // Pre-seed local database with a podcast and an episode
      final pod = Podcast(
        rssUrl: 'https://feeds.example.com/active.xml',
        title: 'Active Podcast',
        description: 'Test Podcast',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(pod);

      final ep = Episode(
        podcastId: podId,
        podcastRss: 'https://feeds.example.com/active.xml',
        guid: 'guid-ep-1',
        title: 'Episode One',
        description: 'Description',
        mediaUrl: 'https://media.example.com/ep1.mp3',
        publishedAt: DateTime.now(),
        duration: 1000,
        position: 0,
        isPlayed: false,
        imageUrl: '',
      );
      await db.insertEpisodes([ep]);

      // Enqueue offline action locally
      final localAction = GPodderAction(
        podcast: 'https://feeds.example.com/active.xml',
        episode: 'https://media.example.com/ep1.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 995,
        started: 0,
        total: 1000,
      );
      await db.enqueueAction(localAction);

      // Seed remote server with an episode action for remote sync test
      final remoteAction = GPodderAction(
        podcast: 'https://feeds.example.com/active.xml',
        episode: 'https://media.example.com/ep1.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 500,
        started: 0,
        total: 1000,
      );
      mockServer.seedEpisodeActions([remoteAction]);

      final syncService = SyncService(
        apiClient: GPodderApiClient(),
        storage: storage,
        db: db,
      );

      final result = await syncService.performFullSync();
      expect(result, isTrue);

      // Local action should have been pushed to mock server
      final serverActions = mockServer.getStoredEpisodeActions();
      expect(serverActions.any((a) => a.position == 995), isTrue);

      // Local queue should be marked synced (no pending actions left)
      final pendingAfter = await db.getPendingActions();
      expect(pendingAfter, isEmpty);

      // Secure storage should have saved last action timestamp
      final savedTs = await storage.read(SecureStorageService.keyLastActionTimestamp);
      expect(savedTs, isNotNull);
      expect(int.parse(savedTs!), greaterThan(0));
    });

    test('Retains offline queue in DB when mock server returns 500 server error', () async {
      final storage = TestSecureStorageService(
        serverUrl: mockServer.baseUrl,
        username: 'syncuser',
        password: 'syncpassword',
      );

      final action = GPodderAction(
        podcast: 'https://feeds.example.com/fail.xml',
        episode: 'https://media.example.com/ep.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 120,
        started: 0,
        total: 600,
      );
      await db.enqueueAction(action);

      // Inject 500 Server Error into Mock Server
      mockServer.simulatedErrorCode = 500;

      final syncService = SyncService(
        apiClient: GPodderApiClient(),
        storage: storage,
        db: db,
      );

      final result = await syncService.pushPendingActions();
      expect(result, isFalse);

      // Actions must remain pending in DB for future retry
      final pending = await db.getPendingActions();
      expect(pending.length, 1);
    });
  });
}
