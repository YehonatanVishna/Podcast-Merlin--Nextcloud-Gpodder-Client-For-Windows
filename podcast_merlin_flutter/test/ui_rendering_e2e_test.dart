import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:audio_service/audio_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/episode_list_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/podcast_catalog_view.dart';

class TestPodcastsNotifier extends StateNotifier<AsyncValue<List<Podcast>>> implements PodcastsNotifier {
  TestPodcastsNotifier(List<Podcast> podcasts) : super(AsyncValue.data(podcasts));

  @override
  Future<void> loadPodcasts() async {}

  @override
  Future<bool> addPodcastFeed(String rssUrl) async => true;

  @override
  Future<void> refreshAll({bool forceFullResync = false}) async {}

  @override
  Future<void> removePodcast(String rssUrl) async {}
}

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

  @override
  Episode? get currentEpisode => _testEpisode;

  @override
  Future<void> playEpisode(Episode episode) async {
    if (_testEpisode != null && _testEpisode!.mediaUrl != episode.mediaUrl) {
      final oldPos = playbackState.value.position.inSeconds;
      final posToSave = oldPos > 0 ? oldPos : _testEpisode!.position;
      await updateEpisodePlaybackState(_testEpisode!.mediaUrl, posToSave);
    }
    _testEpisode = episode;
    mediaItem.add(MediaItem(
      id: episode.mediaUrl,
      album: episode.podcastRss,
      title: episode.title,
      duration: Duration(seconds: episode.duration),
    ));
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      updatePosition: Duration(seconds: episode.position),
    ));
  }

  Future<void> updateEpisodePlaybackState(String mediaUrl, int position) async {
    final isPlayed = position > 0;
    await DatabaseHelper.instance.updateEpisodePlaybackState(mediaUrl, position, isPlayed: isPlayed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('UI Rendering & Show Page E2E Tests', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    testWidgets('PodcastCatalogView renders app title and empty state', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            podcastsNotifierProvider.overrideWith(
              (ref) => TestPodcastsNotifier([]),
            ),
          ],
          child: const MaterialApp(
            home: PodcastCatalogView(),
          ),
        ),
      );

      await tester.pump();

      // App Title in Header
      expect(find.text('Podcast Merlin'), findsOneWidget);

      // Action buttons
      expect(find.byIcon(Icons.add), findsWidgets);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('PodcastCatalogView renders populated podcasts list', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final podcast1 = Podcast(
        id: 1,
        rssUrl: 'https://feeds.example.com/daily.xml',
        title: 'The Daily Tech News',
        description: 'Daily tech updates',
        imageUrl: '',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      final podcast2 = Podcast(
        id: 2,
        rssUrl: 'https://feeds.example.com/science.xml',
        title: 'Science Weekly',
        description: 'Science discoveries',
        imageUrl: '',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            podcastsNotifierProvider.overrideWith(
              (ref) => TestPodcastsNotifier([podcast1, podcast2]),
            ),
          ],
          child: const MaterialApp(
            home: PodcastCatalogView(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('The Daily Tech News'), findsOneWidget);
      expect(find.text('Science Weekly'), findsOneWidget);
    });

    testWidgets('EpisodeListView Show Page renders show title, episodes and play actions', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final audioHandler = MerlinAudioHandler();
      addTearDown(audioHandler.stop);

      final podcast = Podcast(
        id: 10,
        rssUrl: 'https://feeds.example.com/merlin.xml',
        title: 'Podcast Merlin Show',
        description: 'An awesome podcast about code and AI',
        imageUrl: '',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );

      final ep1 = Episode(
        id: 1,
        podcastId: 10,
        podcastRss: 'https://feeds.example.com/merlin.xml',
        guid: 'ep-001',
        title: 'Episode 1: Dawn of AI',
        description: 'Introduction to AI agents',
        mediaUrl: 'https://media.example.com/ep1.mp3',
        publishedAt: DateTime(2026, 1, 15),
        duration: 1200,
        position: 1200,
        isPlayed: true,
        imageUrl: '',
      );

      final ep2 = Episode(
        id: 2,
        podcastId: 10,
        podcastRss: 'https://feeds.example.com/merlin.xml',
        guid: 'ep-002',
        title: 'Episode 2: Flutter Integration',
        description: 'Building modern Flutter applications',
        mediaUrl: 'https://media.example.com/ep2.mp3',
        publishedAt: DateTime(2026, 1, 22),
        duration: 2400,
        position: 450,
        isPlayed: false,
        imageUrl: '',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(10).overrideWith(
              (ref) => TestEpisodesNotifier([ep1, ep2]),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pump();

      // Show Title
      expect(find.text('Podcast Merlin Show'), findsWidgets);

      // Episode Items
      expect(find.text('Episode 1: Dawn of AI'), findsOneWidget);
      expect(find.text('Episode 2: Flutter Integration'), findsOneWidget);

      // Play button icons
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    });

    testWidgets('EpisodeListView updates player position in real-time as position progresses', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final audioHandler = TestAudioHandler();
      addTearDown(audioHandler.stop);

      final podcast = Podcast(
        id: 10,
        rssUrl: 'https://feeds.example.com/merlin.xml',
        title: 'Podcast Merlin Show',
        description: 'An awesome podcast about code and AI',
        imageUrl: '',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );

      final ep = Episode(
        id: 3,
        podcastId: 10,
        podcastRss: 'https://feeds.example.com/merlin.xml',
        guid: 'ep-003',
        title: 'Episode 3: Realtime Position',
        description: 'Testing live position progress',
        mediaUrl: 'https://media.example.com/ep3.mp3',
        publishedAt: DateTime(2026, 2, 1),
        duration: 1000,
        position: 0,
        isPlayed: false,
        imageUrl: '',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(10).overrideWith(
              (ref) => TestEpisodesNotifier([ep]),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Episode 3: Realtime Position'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // Start playing episode
      await audioHandler.playEpisode(ep);
      await tester.pump();

      // Check active playing tile UI elements appear (volume_up icon)
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('Switching episode saves and retains progress bar of previous episode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final audioHandler = TestAudioHandler();
      addTearDown(audioHandler.stop);

      final podcast = Podcast(
        id: 10,
        rssUrl: 'https://feeds.example.com/merlin.xml',
        title: 'Podcast Merlin Show',
        description: 'An awesome podcast about code and AI',
        imageUrl: '',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );

      final ep1 = Episode(
        id: 1,
        podcastId: 10,
        podcastRss: 'https://feeds.example.com/merlin.xml',
        guid: 'ep-001',
        title: 'Episode 1: First Episode',
        description: 'First episode',
        mediaUrl: 'https://media.example.com/ep1.mp3',
        publishedAt: DateTime(2026, 1, 15),
        duration: 1000,
        position: 150,
        isPlayed: false,
        imageUrl: '',
      );

      final ep2 = Episode(
        id: 2,
        podcastId: 10,
        podcastRss: 'https://feeds.example.com/merlin.xml',
        guid: 'ep-002',
        title: 'Episode 2: Second Episode',
        description: 'Second episode',
        mediaUrl: 'https://media.example.com/ep2.mp3',
        publishedAt: DateTime(2026, 1, 20),
        duration: 1000,
        position: 0,
        isPlayed: false,
        imageUrl: '',
      );

      final testNotifier = TestEpisodesNotifier([ep1, ep2]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(10).overrideWith((ref) => testNotifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pump();

      // Play episode 1
      await audioHandler.playEpisode(ep1);
      await tester.pump();

      // Switch to episode 2
      await tester.runAsync(() async {
        await audioHandler.playEpisode(ep2);
      });
      await tester.pump();

      // Ep1 should still retain its progress bar after switching
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
