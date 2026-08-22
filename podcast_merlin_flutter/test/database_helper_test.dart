import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/gpodder_action.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseHelper Comprehensive Unit Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    test('insertOrUpdatePodcast inserts new podcast and updates existing', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/podcast.xml',
        title: 'Merlin Show',
        description: 'Original Description',
        imageUrl: 'https://example.com/logo.png',
        link: 'https://example.com',
        lastUpdated: DateTime.utc(2026, 1, 1),
      );

      final id1 = await db.insertOrUpdatePodcast(podcast);
      expect(id1, greaterThan(0));

      final fetched1 = await db.getPodcastByRssUrl('https://example.com/podcast.xml');
      expect(fetched1, isNotNull);
      expect(fetched1!.title, 'Merlin Show');
      expect(fetched1.description, 'Original Description');

      final updatedPodcast = Podcast(
        id: id1,
        rssUrl: 'https://example.com/podcast.xml',
        title: 'Merlin Show (Updated)',
        description: 'Updated Description',
        imageUrl: 'https://example.com/new_logo.png',
        link: 'https://example.com',
        lastUpdated: DateTime.utc(2026, 1, 2),
      );

      final id2 = await db.insertOrUpdatePodcast(updatedPodcast);
      expect(id2, id1);

      final fetched2 = await db.getPodcastById(id1);
      expect(fetched2!.title, 'Merlin Show (Updated)');
      expect(fetched2.description, 'Updated Description');
    });

    test('markPodcastDead, markPodcastHealthy and getDeadPodcasts track dead feed status', () async {
      final podcast = const Podcast(
        rssUrl: 'https://example.com/dead_test.xml',
        title: 'Dead Test Show',
        description: 'Testing dead feed state',
        imageUrl: '',
        link: '',
      );

      await db.insertOrUpdatePodcast(podcast);

      // Mark podcast dead
      await db.markPodcastDead('https://example.com/dead_test.xml', 'HTTP 403 Forbidden');
      
      final deadList = await db.getDeadPodcasts();
      expect(deadList.length, equals(1));
      expect(deadList.first.isDead, isTrue);
      expect(deadList.first.lastFeedError, equals('HTTP 403 Forbidden'));
      expect(deadList.first.feedErrorCount, equals(1));

      // Mark podcast healthy
      await db.markPodcastHealthy('https://example.com/dead_test.xml');
      
      final healthyPod = await db.getPodcastByRssUrl('https://example.com/dead_test.xml');
      expect(healthyPod!.isDead, isFalse);
      expect(healthyPod.lastFeedError, isNull);
      expect(healthyPod.feedErrorCount, equals(0));
    });

    test('deletePodcastByUrl removes podcast and associated episodes', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/to_delete.xml',
        title: 'Podcast To Delete',
        description: 'Desc',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );

      final podcastId = await db.insertOrUpdatePodcast(podcast);
      final episode = Episode(
        podcastId: podcastId,
        podcastRss: 'https://example.com/to_delete.xml',
        guid: 'ep-delete-1',
        title: 'Ep Delete 1',
        description: '',
        mediaUrl: 'https://example.com/audio_del.mp3',
        publishedAt: DateTime.now(),
        duration: 300,
        position: 0,
        isPlayed: false,
        imageUrl: '',
      );

      await db.insertEpisodes([episode]);

      final epBefore = await db.getEpisodesForPodcast(podcastId);
      expect(epBefore.length, 1);

      await db.deletePodcastByUrl('https://example.com/to_delete.xml');

      final podAfter = await db.getPodcastById(podcastId);
      expect(podAfter, isNull);
    });

    test('updateEpisodeProgress updates database playback position and played status', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/rss.xml',
        title: 'Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podcastId = await db.insertOrUpdatePodcast(podcast);

      final episode = Episode(
        podcastId: podcastId,
        podcastRss: 'https://example.com/rss.xml',
        guid: 'ep-pos-1',
        title: 'Pos Ep',
        description: '',
        mediaUrl: 'https://example.com/pos.mp3',
        publishedAt: DateTime.now(),
        duration: 1000,
        position: 0,
        isPlayed: false,
        imageUrl: '',
      );
      await db.insertEpisodes([episode]);

      // Update position
      await db.updateEpisodeProgress('https://example.com/pos.mp3', 450, false);
      final updatedEp1 = await db.getEpisodeByMediaUrl('https://example.com/pos.mp3');
      expect(updatedEp1!.position, 450);
      expect(updatedEp1.isPlayed, false);

      // Mark played
      await db.updateEpisodeProgress('https://example.com/pos.mp3', 1000, true);
      final updatedEp2 = await db.getEpisodeByMediaUrl('https://example.com/pos.mp3');
      expect(updatedEp2!.isPlayed, true);
    });

    test('Episode filtering (all, unplayed, finished) in Database queries', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/filter.xml',
        title: 'Filter Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podcastId = await db.insertOrUpdatePodcast(podcast);

      final epUnplayed = Episode(
        podcastId: podcastId,
        podcastRss: 'https://example.com/filter.xml',
        guid: 'unplayed-1',
        title: 'Unplayed Ep',
        description: '',
        mediaUrl: 'https://example.com/unplayed.mp3',
        publishedAt: DateTime.now(),
        duration: 600,
        position: 100,
        isPlayed: false,
        imageUrl: '',
      );

      final epFinished = Episode(
        podcastId: podcastId,
        podcastRss: 'https://example.com/filter.xml',
        guid: 'finished-1',
        title: 'Finished Ep',
        description: '',
        mediaUrl: 'https://example.com/finished.mp3',
        publishedAt: DateTime.now(),
        duration: 600,
        position: 600,
        isPlayed: true,
        imageUrl: '',
      );

      await db.insertEpisodes([epUnplayed, epFinished]);

      final allEps = await db.getEpisodesForPodcast(podcastId, filter: EpisodeFilter.all);
      expect(allEps.length, 2);

      final unplayedEps = await db.getEpisodesForPodcast(podcastId, filter: EpisodeFilter.unplayed);
      expect(unplayedEps.length, 1);
      expect(unplayedEps.first.guid, 'unplayed-1');

      final finishedEps = await db.getEpisodesForPodcast(podcastId, filter: EpisodeFilter.finished);
      expect(finishedEps.length, 1);
      expect(finishedEps.first.guid, 'finished-1');
    });

    test('gPodder Action queue management', () async {
      final action1 = GPodderAction(
        podcast: 'https://example.com/pod.xml',
        episode: 'https://example.com/ep1.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 120,
        started: 0,
        total: 1000,
      );

      final action2 = GPodderAction(
        podcast: 'https://example.com/pod.xml',
        episode: 'https://example.com/ep2.mp3',
        action: 'play',
        timestamp: DateTime.now(),
        position: 300,
        started: 0,
        total: 1000,
      );

      final id1 = await db.enqueueAction(action1);
      final id2 = await db.enqueueAction(action2);
      expect(id1, greaterThan(0));
      expect(id2, greaterThan(0));

      final pendingBefore = await db.getPendingActions();
      expect(pendingBefore.length, 2);

      await db.markActionsSynced([id1, id2]);

      final pendingAfter = await db.getPendingActions();
      expect(pendingAfter.isEmpty, isTrue);
    });

    test('refreshing podcast feed or adding new episodes preserves existing episode playback positions and played status', () async {
      final podcast = const Podcast(
        rssUrl: 'https://example.com/refresh_test.xml',
        title: 'Refresh Test Podcast',
        description: 'Test Description',
        imageUrl: 'https://example.com/image.png',
        link: 'https://example.com',
      );

      // 1. Initial subscription / save feed
      final podcastId = await db.insertOrUpdatePodcast(podcast);

      final episode1 = Episode(
        podcastId: podcastId,
        podcastRss: 'https://example.com/refresh_test.xml',
        guid: 'ep-1',
        title: 'Episode 1',
        description: 'Desc 1',
        mediaUrl: 'https://example.com/ep1.mp3',
        publishedAt: DateTime.now().subtract(const Duration(days: 2)),
        duration: 1000,
        position: 0,
        isPlayed: false,
        imageUrl: '',
      );

      await db.insertEpisodes([episode1]);

      // 2. User plays episode 1 to position 500
      await db.updateEpisodeProgress('https://example.com/ep1.mp3', 500, false);

      final ep1BeforeRefresh = await db.getEpisodeByMediaUrl('https://example.com/ep1.mp3');
      expect(ep1BeforeRefresh!.position, equals(500));

      // 3. Podcast feed is refreshed (new episode 2 is added)
      final podcastFromRss = const Podcast(
        rssUrl: 'https://example.com/refresh_test.xml',
        title: 'Refresh Test Podcast (Updated)',
        description: 'Test Description Updated',
        imageUrl: 'https://example.com/image.png',
        link: 'https://example.com',
      );

      final refreshedPodId = await db.insertOrUpdatePodcast(podcastFromRss);
      expect(refreshedPodId, equals(podcastId));

      // Refreshed episodes from RSS feed (episode 1 with pos 0 + new episode 2 with pos 0)
      final refreshedEpisodesFromRss = [
        Episode(
          podcastId: refreshedPodId,
          podcastRss: 'https://example.com/refresh_test.xml',
          guid: 'ep-1',
          title: 'Episode 1 (Updated)',
          description: 'Desc 1',
          mediaUrl: 'https://example.com/ep1.mp3',
          publishedAt: DateTime.now().subtract(const Duration(days: 2)),
          duration: 1000,
          position: 0,
          isPlayed: false,
          imageUrl: '',
        ),
        Episode(
          podcastId: refreshedPodId,
          podcastRss: 'https://example.com/refresh_test.xml',
          guid: 'ep-2',
          title: 'Episode 2 (New)',
          description: 'Desc 2',
          mediaUrl: 'https://example.com/ep2.mp3',
          publishedAt: DateTime.now(),
          duration: 1200,
          position: 0,
          isPlayed: false,
          imageUrl: '',
        ),
      ];

      await db.saveEpisodesBatch(refreshedEpisodesFromRss);

      // 4. Verify episode 1 still has position 500 and episode 2 was added
      final ep1AfterRefresh = await db.getEpisodeByMediaUrl('https://example.com/ep1.mp3');
      expect(ep1AfterRefresh, isNotNull);
      expect(ep1AfterRefresh!.position, equals(500));
      expect(ep1AfterRefresh.title, equals('Episode 1 (Updated)'));

      final ep2AfterRefresh = await db.getEpisodeByMediaUrl('https://example.com/ep2.mp3');
      expect(ep2AfterRefresh, isNotNull);
      expect(ep2AfterRefresh!.position, equals(0));
    });
  });
}
