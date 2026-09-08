import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/player_dock.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/queue_bottom_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/sleep_timer_bottom_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/playback_speed_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('playback_queue');
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');
  });

  group('DatabaseHelper Queue Persistence CRUD Tests', () {
    test('addToQueue appends to bottom when playNext is false', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/show.xml',
        title: 'Queue Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/show.xml',
        guid: 'ep-1',
        title: 'Episode 1',
        description: '',
        mediaUrl: 'https://example.com/ep1.mp3',
        publishedAt: DateTime(2026, 1, 1),
        duration: 1000,
        imageUrl: '',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/show.xml',
        guid: 'ep-2',
        title: 'Episode 2',
        description: '',
        mediaUrl: 'https://example.com/ep2.mp3',
        publishedAt: DateTime(2026, 1, 2),
        duration: 1200,
        imageUrl: '',
      );

      await db.insertEpisodes([ep1, ep2]);
      final savedEp1 = await db.getEpisodeByGuid('ep-1');
      final savedEp2 = await db.getEpisodeByGuid('ep-2');

      expect(savedEp1, isNotNull);
      expect(savedEp2, isNotNull);

      await db.addToQueue(savedEp1!, playNext: false);
      await db.addToQueue(savedEp2!, playNext: false);

      final queue = await db.getQueue();
      expect(queue.length, equals(2));
      expect(queue[0].guid, equals('ep-1'));
      expect(queue[1].guid, equals('ep-2'));
      expect(queue[0].podcastRss, equals('https://example.com/show.xml'));
    });

    test('addToQueue inserts at top when playNext is true', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/show.xml',
        title: 'Queue Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/show.xml',
        guid: 'ep-1',
        title: 'Episode 1',
        description: '',
        mediaUrl: 'https://example.com/ep1.mp3',
        imageUrl: '',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/show.xml',
        guid: 'ep-2',
        title: 'Episode 2',
        description: '',
        mediaUrl: 'https://example.com/ep2.mp3',
        imageUrl: '',
      );
      final epPlayNext = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/show.xml',
        guid: 'ep-next',
        title: 'Play Next Ep',
        description: '',
        mediaUrl: 'https://example.com/ep_next.mp3',
        imageUrl: '',
      );

      await db.insertEpisodes([ep1, ep2, epPlayNext]);
      final s1 = await db.getEpisodeByGuid('ep-1');
      final s2 = await db.getEpisodeByGuid('ep-2');
      final sNext = await db.getEpisodeByGuid('ep-next');

      await db.addToQueue(s1!, playNext: false);
      await db.addToQueue(s2!, playNext: false);
      // Insert sNext with playNext: true
      await db.addToQueue(sNext!, playNext: true);

      final queue = await db.getQueue();
      expect(queue.length, equals(3));
      expect(queue[0].guid, equals('ep-next'));
      expect(queue[1].guid, equals('ep-1'));
      expect(queue[2].guid, equals('ep-2'));
    });

    test('reorderQueue and removeFromQueue update database ordering', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/show.xml',
        title: 'Queue Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final eps = List.generate(
        3,
        (i) => Episode(
          podcastId: podId,
          podcastRss: 'https://example.com/show.xml',
          guid: 'ep-$i',
          title: 'Ep $i',
          description: '',
          mediaUrl: 'https://example.com/ep$i.mp3',
          imageUrl: '',
        ),
      );
      await db.insertEpisodes(eps);
      final savedEps = [
        (await db.getEpisodeByGuid('ep-0'))!,
        (await db.getEpisodeByGuid('ep-1'))!,
        (await db.getEpisodeByGuid('ep-2'))!,
      ];

      for (final ep in savedEps) {
        await db.addToQueue(ep, playNext: false);
      }

      var queue = await db.getQueue();
      expect(queue.map((e) => e.guid).toList(), ['ep-0', 'ep-1', 'ep-2']);

      // Move ep-0 to index 2 (end)
      await db.reorderQueue(0, 2);
      queue = await db.getQueue();
      expect(queue.map((e) => e.guid).toList(), ['ep-1', 'ep-2', 'ep-0']);

      // Remove ep-2
      await db.removeFromQueue(savedEps[2].id!);
      queue = await db.getQueue();
      expect(queue.map((e) => e.guid).toList(), ['ep-1', 'ep-0']);

      // Clear queue
      await db.clearQueue();
      queue = await db.getQueue();
      expect(queue, isEmpty);
    });

    test('deleting podcast cascade-deletes queued items', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/cascade.xml',
        title: 'Cascade Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/cascade.xml',
        guid: 'cascade-ep',
        title: 'Cascade Ep',
        description: '',
        mediaUrl: 'https://example.com/cascade.mp3',
        imageUrl: '',
      );
      await db.insertEpisodes([ep]);
      final saved = await db.getEpisodeByGuid('cascade-ep');
      await db.addToQueue(saved!);

      expect((await db.getQueue()).length, equals(1));

      // Delete podcast
      await db.deletePodcast(podId);

      // Queue should now be empty due to ON DELETE CASCADE
      expect((await db.getQueue()), isEmpty);
    });
  });

  group('MerlinAudioHandler Queue & Stream Integration Tests', () {
    late MerlinAudioHandler audioHandler;

    setUp(() {
      audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
    });

    tearDown(() {
      audioHandler.dispose();
    });

    test('addToQueue, removeFromQueue, and clearQueue update memory and streams', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/stream.xml',
        title: 'Stream Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/stream.xml',
        guid: 'stream-1',
        title: 'Stream 1',
        description: '',
        mediaUrl: 'https://example.com/stream1.mp3',
        imageUrl: '',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/stream.xml',
        guid: 'stream-2',
        title: 'Stream 2',
        description: '',
        mediaUrl: 'https://example.com/stream2.mp3',
        imageUrl: '',
      );

      await db.insertEpisodes([ep1, ep2]);
      final s1 = (await db.getEpisodeByGuid('stream-1'))!;
      final s2 = (await db.getEpisodeByGuid('stream-2'))!;

      final queueEvents = <List<Episode>>[];
      final sub = audioHandler.queueStream.listen(queueEvents.add);

      await audioHandler.addToQueue(s1, playNext: false);
      expect(audioHandler.currentQueue.length, equals(1));
      expect(audioHandler.currentQueue.first.guid, equals('stream-1'));

      await audioHandler.addToQueue(s2, playNext: true);
      expect(audioHandler.currentQueue.length, equals(2));
      expect(audioHandler.currentQueue.first.guid, equals('stream-2'));

      // Reorder
      await audioHandler.reorderQueue(0, 1);
      expect(audioHandler.currentQueue.first.guid, equals('stream-1'));

      // Remove s1
      await audioHandler.removeFromQueue(s1.id!);
      expect(audioHandler.currentQueue.length, equals(1));
      expect(audioHandler.currentQueue.first.guid, equals('stream-2'));

      // Clear
      await audioHandler.clearQueue();
      expect(audioHandler.currentQueue, isEmpty);

      await sub.cancel();
      expect(queueEvents, isNotEmpty);
    });

    test('playNextInQueue pops and plays next episode', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/next.xml',
        title: 'Next Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/next.xml',
        guid: 'next-1',
        title: 'Next Episode 1',
        description: '',
        mediaUrl: 'https://example.com/next1.mp3',
        imageUrl: '',
      );
      await db.insertEpisodes([ep]);
      final saved = (await db.getEpisodeByGuid('next-1'))!;

      await audioHandler.addToQueue(saved);
      expect(audioHandler.currentQueue.length, equals(1));

      await audioHandler.playNextInQueue();

      // Should have popped from queue
      expect(audioHandler.currentQueue, isEmpty);
      expect(audioHandler.currentEpisode?.guid, equals('next-1'));
    });

    test('skipToNext advances to queued episode when queue is non-empty', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/skip.xml',
        title: 'Skip Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/skip.xml',
        guid: 'skip-1',
        title: 'Playing Episode',
        description: '',
        mediaUrl: 'https://example.com/skip1.mp3',
        imageUrl: '',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/skip.xml',
        guid: 'skip-2',
        title: 'Queued Episode',
        description: '',
        mediaUrl: 'https://example.com/skip2.mp3',
        imageUrl: '',
      );

      await db.insertEpisodes([ep1, ep2]);
      final s1 = (await db.getEpisodeByGuid('skip-1'))!;
      final s2 = (await db.getEpisodeByGuid('skip-2'))!;

      await audioHandler.playEpisode(s1);
      await audioHandler.addToQueue(s2);

      expect(audioHandler.currentEpisode?.guid, equals('skip-1'));
      expect(audioHandler.currentQueue.length, equals(1));

      await audioHandler.skipToNext();

      expect(audioHandler.currentEpisode?.guid, equals('skip-2'));
      expect(audioHandler.currentQueue, isEmpty);
    });

    test('queue auto-advances to next episode on playback completion', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/auto.xml',
        title: 'Auto Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/auto.xml',
        guid: 'auto-1',
        title: 'Auto Ep 1',
        description: '',
        mediaUrl: 'https://example.com/auto1.mp3',
        duration: 600,
        imageUrl: '',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/auto.xml',
        guid: 'auto-2',
        title: 'Auto Ep 2',
        description: '',
        mediaUrl: 'https://example.com/auto2.mp3',
        duration: 900,
        imageUrl: '',
      );

      await db.insertEpisodes([ep1, ep2]);
      final s1 = (await db.getEpisodeByGuid('auto-1'))!;
      final s2 = (await db.getEpisodeByGuid('auto-2'))!;

      await audioHandler.playEpisode(s1);
      await audioHandler.addToQueue(s2);

      expect(audioHandler.currentEpisode?.guid, equals('auto-1'));
      expect(audioHandler.currentQueue.length, equals(1));

      // Trigger playback completion
      await audioHandler.onPlaybackCompletedForTesting();

      // ep1 should be marked played in database
      final ep1Db = await db.getEpisodeByGuid('auto-1');
      expect(ep1Db!.isPlayed, isTrue);

      // And ep2 should now be playing automatically!
      expect(audioHandler.currentEpisode?.guid, equals('auto-2'));
      expect(audioHandler.currentQueue, isEmpty);
    });
  });

  group('MerlinAudioHandler Sleep Timer Tests', () {
    late MerlinAudioHandler audioHandler;

    setUp(() {
      audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
    });

    tearDown(() {
      audioHandler.dispose();
    });

    test('setSleepTimer and cancelSleepTimer control countdown state', () async {
      expect(audioHandler.isSleepTimerActive, isFalse);
      expect(audioHandler.sleepTimerRemaining, isNull);

      audioHandler.setSleepTimer(const Duration(minutes: 15));

      expect(audioHandler.isSleepTimerActive, isTrue);
      expect(audioHandler.sleepTimerMode, equals(SleepTimerMode.duration));
      expect(audioHandler.sleepTimerRemaining?.inMinutes, equals(15));
      expect(audioHandler.isSleepTimerEndOfEpisode, isFalse);

      audioHandler.cancelSleepTimer();

      expect(audioHandler.isSleepTimerActive, isFalse);
      expect(audioHandler.sleepTimerMode, equals(SleepTimerMode.none));
      expect(audioHandler.sleepTimerRemaining, isNull);
    });

    test('sleep timer pauses playback when countdown expires', () async {
      audioHandler.setSleepTimer(const Duration(seconds: 1));

      expect(audioHandler.isSleepTimerActive, isTrue);

      // Wait for timer to expire
      await Future.delayed(const Duration(milliseconds: 1200));

      expect(audioHandler.isSleepTimerActive, isFalse);
      expect(audioHandler.sleepTimerRemaining, isNull);
    });

    test('sleep timer endOfEpisode mode stops playback and does not auto-advance queue', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/end-ep.xml',
        title: 'End Ep Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/end-ep.xml',
        guid: 'end-1',
        title: 'Current Ep',
        description: '',
        mediaUrl: 'https://example.com/end1.mp3',
        duration: 300,
        imageUrl: '',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/end-ep.xml',
        guid: 'end-2',
        title: 'Queued Ep',
        description: '',
        mediaUrl: 'https://example.com/end2.mp3',
        duration: 300,
        imageUrl: '',
      );

      await db.insertEpisodes([ep1, ep2]);
      final s1 = (await db.getEpisodeByGuid('end-1'))!;
      final s2 = (await db.getEpisodeByGuid('end-2'))!;

      await audioHandler.playEpisode(s1);
      await audioHandler.addToQueue(s2);

      // Set Sleep Timer to End of Episode
      audioHandler.setSleepTimerEndOfEpisode();
      expect(audioHandler.isSleepTimerEndOfEpisode, isTrue);
      expect(audioHandler.isSleepTimerActive, isTrue);

      // When playback completes:
      await audioHandler.onPlaybackCompletedForTesting();

      // Sleep timer should have cancelled
      expect(audioHandler.isSleepTimerActive, isFalse);

      // Should NOT have advanced to ep2 because of End of Episode sleep timer!
      expect(audioHandler.currentQueue.length, equals(1));
      expect(audioHandler.currentQueue.first.guid, equals('end-2'));
    });
  });

  group('Configurable Seek Durations & Playback Speed Tests', () {
    late MerlinAudioHandler audioHandler;

    setUp(() {
      audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
    });

    tearDown(() {
      audioHandler.dispose();
    });

    test('setSeekDurations updates values and persists to storage', () async {
      expect(audioHandler.rewindDuration, equals(10));
      expect(audioHandler.fastForwardDuration, equals(30));

      await audioHandler.setSeekDurations(rewind: 15, fastForward: 45);

      expect(audioHandler.rewindDuration, equals(15));
      expect(audioHandler.fastForwardDuration, equals(45));

      final storage = SecureStorageService();
      expect(await storage.read(SecureStorageService.keyRewindDuration), equals('15'));
      expect(await storage.read(SecureStorageService.keyFastForwardDuration), equals('45'));
    });

    test('setSpeed adjusts playback speed', () async {
      await audioHandler.setSpeed(1.5);
      expect(audioHandler.speed, equals(1.5));

      await audioHandler.setSpeed(2.0);
      expect(audioHandler.speed, equals(2.0));
    });
  });

  group('UI Widgets Tests for Phase 1 Controls', () {
    testWidgets('PlayerDock displays Queue, Sleep Timer, and configured seek durations', (tester) async {
      late MerlinAudioHandler audioHandler;
      await tester.runAsync(() async {
        audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});

        final ep = Episode(
          id: 1,
          podcastId: 1,
          podcastRss: 'https://example.com/rss.xml',
          guid: 'test-ep',
          title: 'Player Dock Test Episode',
          description: '',
          mediaUrl: 'https://example.com/test.mp3',
          duration: 1800,
          position: 300,
          imageUrl: '',
        );

        await audioHandler.playEpisode(ep);
      });
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              bottomNavigationBar: PlayerDock(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Queue button should be present
      expect(find.byIcon(Icons.queue_music), findsOneWidget);

      // Sleep timer button should be present
      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);

      // Speed button should be present
      expect(find.byIcon(Icons.speed), findsOneWidget);

      // Play/pause button should be present (playing, so pause icon)
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

      // Title should be visible
      expect(find.text('Player Dock Test Episode'), findsOneWidget);
    });

    testWidgets('QueueBottomSheet renders empty state and list correctly', (tester) async {
      final audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: QueueBottomSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Up Next Queue'), findsOneWidget);
      expect(find.text('Queue is empty'), findsOneWidget);
    });

    testWidgets('SleepTimerBottomSheet displays preset options and End of Episode', (tester) async {
      final audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SleepTimerBottomSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('15 minutes'), findsOneWidget);
      expect(find.text('30 minutes'), findsOneWidget);
      expect(find.text('45 minutes'), findsOneWidget);
      expect(find.text('60 minutes'), findsOneWidget);
      expect(find.text('End of Current Episode'), findsOneWidget);
    });

    testWidgets('PlaybackSpeedSheet displays slider and preset options', (tester) async {
      final audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PlaybackSpeedSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Playback Speed'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('1.0x'), findsWidgets);
      expect(find.text('1.5x'), findsOneWidget);
      expect(find.text('2.0x'), findsOneWidget);
    });
  });
}
