import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/episode_list_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestEpisodesNotifier extends StateNotifier<EpisodesState> implements EpisodesNotifier {
  TestEpisodesNotifier(List<Episode> episodes)
      : super(
          EpisodesState(
            episodes: episodes,
            isLoading: false,
            isLoadingMore: false,
            hasMore: false,
          ),
        );

  @override
  Future<void> loadEpisodes({EpisodeFilter? filter, bool silent = false}) async {}

  @override
  Future<void> loadMoreEpisodes() async {}

  @override
  Future<void> refresh({Podcast? podcast}) async {}

  @override
  Future<void> setFilter(EpisodeFilter filter) async {}

  @override
  void updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) {
    if (!mounted || state.episodes.isEmpty) return;
    final index = state.episodes.indexWhere((e) => e.mediaUrl == mediaUrl);
    if (index != -1) {
      final updatedList = List<Episode>.from(state.episodes);
      updatedList[index] = updatedList[index].copyWith(
        position: position,
        isPlayed: isPlayed,
      );
      state = state.copyWith(episodes: updatedList);
    }
  }
}

class TestAudioHandler extends MerlinAudioHandler {
  Episode? _testEpisode;
  final VoidCallback? onReplay;

  TestAudioHandler({this.onReplay});

  @override
  Episode? get currentEpisode => _testEpisode;

  @override
  Future<void> playEpisode(Episode episode) async {
    _testEpisode = episode.isFinished
        ? episode.copyWith(position: 0, isPlayed: false)
        : episode;
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      updatePosition: Duration(seconds: _testEpisode!.position),
    ));
    onReplay?.call();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Episode.isFinished 1-minute remaining logic tests', () {
    test('marks episode finished when exactly 60 seconds (1 min) remain', () {
      const duration = 1800; // 30 minutes
      final epAt60s = Episode(
        guid: 'test-1',
        title: 'Test Episode',
        mediaUrl: 'https://example.com/ep1.mp3',
        description: '',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: duration,
        position: 1740, // 60s remaining
        isPlayed: false,
      );
      expect(epAt60s.isFinished, isTrue);
    });

    test('marks episode finished when less than 60 seconds remain', () {
      const duration = 1800;
      final epNearEnd = Episode(
        guid: 'test-2',
        title: 'Test Episode',
        mediaUrl: 'https://example.com/ep2.mp3',
        description: '',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: duration,
        position: 1775, // 25s remaining
        isPlayed: false,
      );
      expect(epNearEnd.isFinished, isTrue);
    });

    test('does NOT mark episode finished when more than 60 seconds remain', () {
      const duration = 1800;
      final epMidway = Episode(
        guid: 'test-3',
        title: 'Test Episode',
        mediaUrl: 'https://example.com/ep3.mp3',
        description: '',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: duration,
        position: 1739, // 61s remaining
        isPlayed: false,
      );
      expect(epMidway.isFinished, isFalse);

      final epAtZero = Episode(
        guid: 'test-4',
        title: 'Test Episode',
        mediaUrl: 'https://example.com/ep4.mp3',
        description: '',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: duration,
        position: 0,
        isPlayed: false,
      );
      expect(epAtZero.isFinished, isFalse);
    });

    test('marks episode finished when isPlayed is true regardless of position', () {
      final epPlayed = Episode(
        guid: 'test-5',
        title: 'Test Episode',
        mediaUrl: 'https://example.com/ep5.mp3',
        description: '',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 1800,
        position: 0,
        isPlayed: true,
      );
      expect(epPlayed.isFinished, isTrue);
    });

    test('handles short episodes (duration <= 60s) properly', () {
      const duration = 45;
      final epShortUnplayed = Episode(
        guid: 'test-6',
        title: 'Short Episode',
        mediaUrl: 'https://example.com/ep6.mp3',
        description: '',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: duration,
        position: 0,
        isPlayed: false,
      );
      expect(epShortUnplayed.isFinished, isFalse);

      final epShortFinished = Episode(
        guid: 'test-7',
        title: 'Short Episode',
        mediaUrl: 'https://example.com/ep7.mp3',
        description: '',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: duration,
        position: 36, // <= 10s remaining for short clips
        isPlayed: false,
      );
      expect(epShortFinished.isFinished, isTrue);
    });
  });

  group('EpisodeListView Grayed-Out UI Widget Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    testWidgets('Unplayed episode renders with full opacity and normal play icon', (tester) async {
      final podcast = Podcast(
        id: 1,
        rssUrl: 'https://example.com/rss.xml',
        title: 'Test Podcast',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );

      final unplayedEp = Episode(
        id: 101,
        podcastId: 1,
        podcastRss: 'https://example.com/rss.xml',
        guid: 'unplayed-ep',
        title: 'Fresh Unplayed Episode',
        description: 'Episode details here',
        mediaUrl: 'https://example.com/fresh.mp3',
        publishedAt: DateTime(2026, 3, 1),
        duration: 1800,
        position: 200,
        isPlayed: false,
        imageUrl: '',
      );

      final audioHandler = TestAudioHandler();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith(
              (ref) => TestEpisodesNotifier([unplayedEp]),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Title should be visible
      expect(find.text('Fresh Unplayed Episode'), findsOneWidget);

      // Play button should be present
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Should NOT have Played text
      expect(find.textContaining('Played'), findsNothing);

      // Check that AnimatedOpacity has opacity 1.0
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);
      final animatedOpacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacityWidget.opacity, equals(1.0));
    });

    testWidgets('Finished/played episode (<1 min left) renders grayed out (opacity 0.45) with Played badge and replay icon', (tester) async {
      final podcast = Podcast(
        id: 1,
        rssUrl: 'https://example.com/rss.xml',
        title: 'Test Podcast',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );

      // Episode with 40s remaining (< 60s)
      final finishedEp = Episode(
        id: 102,
        podcastId: 1,
        podcastRss: 'https://example.com/rss.xml',
        guid: 'finished-ep',
        title: 'Completed Episode',
        description: 'Episode details for completed ep',
        mediaUrl: 'https://example.com/completed.mp3',
        publishedAt: DateTime(2026, 3, 1),
        duration: 1200,
        position: 1160, // 40 seconds remaining
        isPlayed: false,
        imageUrl: '',
      );

      final audioHandler = TestAudioHandler();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith(
              (ref) => TestEpisodesNotifier([finishedEp]),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Title should be present
      expect(find.text('Completed Episode'), findsOneWidget);

      // Should show 'Played • ' indicator
      expect(find.textContaining('Played'), findsOneWidget);

      // Should show check circle icon
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // Replay icon button should be present instead of standard play
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);

      // Tile should be visibly grayed out with reduced opacity (0.45)
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);
      final animatedOpacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacityWidget.opacity, equals(0.45));
    });

    testWidgets('Episode marked isPlayed=true renders grayed out and modal shows Played badge and Replay option', (tester) async {
      final podcast = Podcast(
        id: 1,
        rssUrl: 'https://example.com/rss.xml',
        title: 'Test Podcast',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );

      final playedEp = Episode(
        id: 103,
        podcastId: 1,
        podcastRss: 'https://example.com/rss.xml',
        guid: 'played-ep',
        title: 'Marked As Played Episode',
        description: 'This is the description in modal',
        mediaUrl: 'https://example.com/played.mp3',
        publishedAt: DateTime(2026, 3, 1),
        duration: 1800,
        position: 0,
        isPlayed: true,
        imageUrl: '',
      );

      final audioHandler = TestAudioHandler();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith(
              (ref) => TestEpisodesNotifier([playedEp]),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check tile is grayed out
      final animatedOpacityWidget = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(animatedOpacityWidget.opacity, equals(0.45));

      // Tap on the tile to open modal sheet
      await tester.tap(find.text('Marked As Played Episode'));
      await tester.pumpAndSettle();

      // Modal should show 'Played' badge and 'Replay Episode' button
      expect(find.text('Played'), findsWidgets);
      expect(find.text('Replay Episode'), findsOneWidget);
      expect(find.byIcon(Icons.replay), findsOneWidget);
    });

    testWidgets('Replaying a finished episode updates state and reflects in UI as unplayed', (tester) async {
      final podcast = Podcast(
        id: 1,
        rssUrl: 'https://example.com/rss.xml',
        title: 'Test Podcast',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );

      final finishedEp = Episode(
        id: 104,
        podcastId: 1,
        podcastRss: 'https://example.com/rss.xml',
        guid: 'finished-to-replay',
        title: 'Replay Me Episode',
        description: 'Testing replay unplayed reflection',
        mediaUrl: 'https://example.com/replay.mp3',
        publishedAt: DateTime(2026, 3, 1),
        duration: 1800,
        position: 1780, // finished (< 1 min remaining)
        isPlayed: true,
        imageUrl: '',
      );

      late TestEpisodesNotifier episodesNotifier;
      late TestAudioHandler audioHandler;

      episodesNotifier = TestEpisodesNotifier([finishedEp]);
      audioHandler = TestAudioHandler(
        onReplay: () {
          episodesNotifier.updateEpisodeProgress(finishedEp.mediaUrl, 0, false);
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith(
              (ref) => episodesNotifier,
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially finished and grayed out
      expect(find.textContaining('Played'), findsOneWidget);
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, equals(0.45));

      // User chooses to replay the episode by tapping the replay button
      await tester.tap(find.byIcon(Icons.replay_rounded));
      await tester.pumpAndSettle();

      // Now reflected in UI as unplayed:
      // 1. Tile is no longer grayed out (opacity 1.0)
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, equals(1.0));

      // 2. 'Played • ' indicator is gone
      expect(find.textContaining('Played'), findsNothing);

      // 3. Trailing icon is now volume_up (actively playing)
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byIcon(Icons.replay_rounded), findsNothing);

      // 4. Progress displays 0:00 / 30:00
      expect(find.textContaining('00:00 / 30:00'), findsOneWidget);
    });

    test('Replaying episode resets database position to 0 and isPlayed to false', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/db-replay.xml',
        title: 'DB Replay Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/db-replay.xml',
        guid: 'ep-db-replay',
        title: 'DB Ep',
        description: '',
        mediaUrl: 'https://example.com/db-replay.mp3',
        publishedAt: DateTime.now(),
        duration: 2000,
        position: 1980,
        isPlayed: true,
        imageUrl: '',
      );
      await db.insertEpisodes([ep]);

      final before = await db.getEpisodeByMediaUrl('https://example.com/db-replay.mp3');
      expect(before!.isPlayed, isTrue);
      expect(before.position, equals(1980));
      expect(before.isFinished, isTrue);

      // Simulate replaying episode
      await db.updateEpisodePlaybackState(ep.mediaUrl, 0, isPlayed: false);

      final after = await db.getEpisodeByMediaUrl('https://example.com/db-replay.mp3');
      expect(after!.isPlayed, isFalse);
      expect(after.position, equals(0));
      expect(after.isFinished, isFalse);

      // Verify it is queried as unplayed
      final unplayed = await db.getEpisodesForPodcast(podId, filter: EpisodeFilter.unplayed);
      expect(unplayed.length, 1);
      expect(unplayed.first.guid, 'ep-db-replay');

      final finished = await db.getEpisodesForPodcast(podId, filter: EpisodeFilter.finished);
      expect(finished, isEmpty);
    });
  });
}
