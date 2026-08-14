import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/models/gpodder_action.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';

class MockDeduplicationApiClient extends GPodderApiClient {
  bool isServerOnline = true;
  List<String> uploadedAdds = [];
  List<String> uploadedRemoves = [];
  List<GPodderAction> uploadedEpisodeActions = [];
  int pingCallCount = 0;

  @override
  Future<bool> pingServer({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    pingCallCount++;
    return isServerOnline;
  }

  @override
  Future<bool> uploadSubscriptionChanges({
    required String serverUrl,
    required String username,
    required String password,
    required List<String> addUrls,
    required List<String> removeUrls,
  }) async {
    final online = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!online) return false;
    uploadedAdds.addAll(addUrls);
    uploadedRemoves.addAll(removeUrls);
    return true;
  }

  @override
  Future<bool> uploadEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    required List<GPodderAction> actions,
  }) async {
    final online = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!online) return false;
    uploadedEpisodeActions.addAll(actions);
    return true;
  }

  @override
  Future<Map<String, dynamic>?> fetchSubscriptions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    final online = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!online) return null;
    return {'add': <String>[], 'remove': <String>[], 'timestamp': 1000};
  }

  @override
  Future<List<GPodderAction>> fetchEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    final online = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!online) return [];
    return [];
  }
}

class TestStorage extends SecureStorageService {
  final Map<String, String> _map = {
    SecureStorageService.keyServerUrl: 'https://gpodder.example.com',
    SecureStorageService.keyUsername: 'testuser',
    SecureStorageService.keyPassword: 'secretpassword',
  };

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Sync Backlog Smart Deduplication & Offline Handshake Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final rawDb = await db.database;
      await rawDb.delete('subscription_backlog');
      await rawDb.delete('gpodder_actions');
      await rawDb.delete('episodes');
      await rawDb.delete('podcasts');
    });

    test('Subscription add followed by remove cancels out to 0 pending events', () async {
      final feedUrl = 'https://example.com/test_feed.xml';

      // User subscribes offline
      await db.queueSubscriptionChange('add', feedUrl);
      var pending = await db.getPendingSubscriptionChanges();
      expect(pending['add'], contains(feedUrl));

      // User unsubscribes offline
      await db.queueSubscriptionChange('remove', feedUrl);
      pending = await db.getPendingSubscriptionChanges();

      // Net result should be empty (both cancelled out!)
      expect((pending['add'] as List), isEmpty);
      expect((pending['remove'] as List), isEmpty);
    });

    test('Subscription remove followed by add cancels out to 0 pending events', () async {
      final feedUrl = 'https://example.com/test_feed_2.xml';

      // User unsubscribes offline
      await db.queueSubscriptionChange('remove', feedUrl);
      var pending = await db.getPendingSubscriptionChanges();
      expect(pending['remove'], contains(feedUrl));

      // User re-subscribes offline
      await db.queueSubscriptionChange('add', feedUrl);
      pending = await db.getPendingSubscriptionChanges();

      // Net result should be empty (both cancelled out!)
      expect((pending['add'] as List), isEmpty);
      expect((pending['remove'] as List), isEmpty);
    });

    test('Duplicate subscription add or remove actions are deduplicated to single item', () async {
      final feedUrl = 'https://example.com/duplicate_feed.xml';

      await db.queueSubscriptionChange('add', feedUrl);
      await db.queueSubscriptionChange('add', feedUrl);

      final pending = await db.getPendingSubscriptionChanges();
      expect((pending['add'] as List).length, equals(1));
    });

    test('Multiple position updates for the same episode update single pending row in-place', () async {
      final podcastUrl = 'https://example.com/podcast.xml';
      final episodeUrl = 'https://example.com/episode1.mp3';

      for (int pos = 10; pos <= 100; pos += 10) {
        final action = GPodderAction(
          podcast: podcastUrl,
          episode: episodeUrl,
          action: 'play',
          timestamp: DateTime.now(),
          position: pos,
          total: 1000,
        );
        await db.queueGPodderAction(action);
      }

      final actions = await db.getPendingActions();
      expect(actions.length, equals(1));
      expect(actions.first.position, equals(100));
    });

    test('pingServer runs before every server request and handles sudden disconnects', () async {
      final apiClient = MockDeduplicationApiClient();
      final storage = TestStorage();
      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      // 1. Server is offline
      apiClient.isServerOnline = false;
      final pod = Podcast(
        rssUrl: 'https://example.com/local.xml',
        title: 'Local Podcast',
        description: '',
        imageUrl: '',
        link: '',
      );
      await db.insertOrUpdatePodcast(pod);

      // Perform sync while server is offline
      final syncResult = await syncService.performFullSync();
      expect(syncResult, isTrue); // Gracefully handles offline fallback without error crash
      expect(apiClient.pingCallCount, greaterThan(0));
      expect(syncService.lastFeedWarnings.any((w) => w.contains('offline')), isTrue);
    });

    test('Online backlog flush pushes deduplicated subscription changes and play positions', () async {
      final apiClient = MockDeduplicationApiClient();
      final storage = TestStorage();
      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      // Queue actions offline
      await db.queueSubscriptionChange('add', 'https://example.com/new_sub.xml');
      await db.queueSubscriptionChange('remove', 'https://example.com/old_sub.xml');
      await db.queueGPodderAction(GPodderAction(
        podcast: 'https://example.com/pod.xml',
        episode: 'https://example.com/ep.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 450,
        total: 900,
      ));

      // Flush backlog when server comes online
      apiClient.isServerOnline = true;
      final pushResult = await syncService.pushPendingBacklog();
      expect(pushResult, isTrue);

      expect(apiClient.uploadedAdds, contains('https://example.com/new_sub.xml'));
      expect(apiClient.uploadedRemoves, contains('https://example.com/old_sub.xml'));
      expect(apiClient.uploadedEpisodeActions.length, equals(1));
      expect(apiClient.uploadedEpisodeActions.first.position, equals(450));

      // Backlog tables should be cleared after successful push
      final pendingSubs = await db.getPendingSubscriptionChanges();
      final pendingActions = await db.getPendingActions();
      expect((pendingSubs['add'] as List), isEmpty);
      expect((pendingSubs['remove'] as List), isEmpty);
      expect(pendingActions, isEmpty);
    });
  });
}
