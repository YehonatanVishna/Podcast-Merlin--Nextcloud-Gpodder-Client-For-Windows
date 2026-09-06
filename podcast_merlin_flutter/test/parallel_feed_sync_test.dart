import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/features/podcasts/rss_feed_parser.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
import 'sync_service_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Parallel Feed Parsing and Insertion Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    test('parseFeedXmlAsync parses feed using background isolate compute', () async {
      final parser = RssFeedParser();
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Parallel Feed Test</title>
    <description>Testing background isolate execution.</description>
    <link>https://example.com/parallel</link>
    <item>
      <title>Episode Parallel 1</title>
      <guid>para-1</guid>
      <enclosure url="https://example.com/para1.mp3"/>
    </item>
  </channel>
</rss>''';

      final result = await parser.parseFeedXmlAsync(xml, 'https://example.com/parallel.xml');
      expect(result.title, equals('Parallel Feed Test'));
      expect(result.episodes.length, equals(1));
      expect(result.episodes.first.guid, equals('para-1'));
    });

    test('performFullSync processes multiple feeds in parallel', () async {
      final storage = TestSecureStorageService(
        serverUrl: 'https://example.com/gpodder',
        username: 'user',
        password: 'pass',
      );
      final apiClient = TestGPodderApiClient();

      apiClient.mockSubscriptionResponse = {
        'add': [
          'https://example.com/feed1.xml',
          'https://example.com/feed2.xml',
          'https://example.com/feed3.xml',
        ],
        'remove': <String>[],
        'timestamp': 1730000000,
      };

      final syncService = SyncService(
        apiClient: apiClient,
        storage: storage,
        db: db,
      );

      final progressDetails = <String>[];
      final success = await syncService.performFullSync(
        onProgress: (stage, detail) {
          if (detail != null) progressDetails.add(detail);
        },
      );

      expect(success, isTrue);

      // Verify dead podcast stubs were inserted in parallel for failing test feeds
      final allPods = await db.getAllPodcasts();
      expect(allPods.length, equals(3));
      final urls = allPods.map((p) => p.rssUrl).toSet();
      expect(urls, contains('https://example.com/feed1.xml'));
      expect(urls, contains('https://example.com/feed2.xml'));
      expect(urls, contains('https://example.com/feed3.xml'));

      expect(progressDetails.any((d) => d.contains('Fetching podcast feeds')), isTrue);
    });
  });
}
