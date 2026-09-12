import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/core/utils/responsive.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/download_center_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/episode_list_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/main_shell.dart';
import 'package:podcast_merlin_flutter/features/ui/views/podcast_catalog_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/settings_view.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/now_playing_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/playback_speed_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/player_dock.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/queue_bottom_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/sleep_timer_bottom_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeSecureStorageService extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _data[key];
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

class TestPodcastsNotifier extends StateNotifier<AsyncValue<List<Podcast>>> implements PodcastsNotifier {
  TestPodcastsNotifier([List<Podcast> podcasts = const []]) : super(AsyncValue.data(podcasts));

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
  TestEpisodesNotifier([List<Episode> episodes = const []])
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
  Future<bool> toggleStar(Episode episode) async => false;

  @override
  void updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late MerlinAudioHandler defaultAudioHandler;
  late EpisodeDownloadService downloadService;
  late FakeSecureStorageService fakeStorage;

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');
    defaultAudioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
    downloadService = EpisodeDownloadService(
      db: db,
      downloadDirResolver: () async => Directory('/tmp'),
    );
    fakeStorage = FakeSecureStorageService();
  });

  tearDown(() async {
    downloadService.dispose();
    await defaultAudioHandler.stop();
  });

  Widget buildAppWithViewport({
    required Widget child,
    required Size size,
    MerlinAudioHandler? audioHandler,
    List<Override> extraOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secureStorageProvider.overrideWithValue(fakeStorage),
        audioHandlerProvider.overrideWithValue(audioHandler ?? defaultAudioHandler),
        episodeDownloadServiceProvider.overrideWithValue(downloadService),
        podcastsNotifierProvider.overrideWith((ref) => TestPodcastsNotifier([])),
        episodesNotifierProvider(null).overrideWith((ref) => TestEpisodesNotifier([])),
        downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(0)),
        downloadedEpisodesCountProvider.overrideWith((ref) => Future.value(0)),
        downloadedEpisodesListProvider.overrideWith((ref) => Future.value([])),
        failedEpisodesListProvider.overrideWith((ref) => Future.value([])),
        activeDownloadsCountProvider.overrideWith((ref) => Stream.value(0)),
        downloadTasksStreamProvider.overrideWith((ref) => Stream.value({})),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    );
  }

  group('ResponsiveBreakpoints and ResponsiveContext Unit Tests', () {
    testWidgets('ResponsiveContext properly detects compact, medium, and expanded', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late bool isCompact;
      late bool isMedium;
      late bool isExpanded;
      late bool isDesktopNav;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMedium = context.isMedium;
              isExpanded = context.isExpanded;
              isDesktopNav = context.isDesktopNav;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isCompact, isTrue);
      expect(isMedium, isFalse);
      expect(isExpanded, isFalse);
      expect(isDesktopNav, isFalse);

      // Change to medium tablet (700x900)
      tester.view.physicalSize = const Size(700, 900);
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMedium = context.isMedium;
              isExpanded = context.isExpanded;
              isDesktopNav = context.isDesktopNav;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isCompact, isFalse);
      expect(isMedium, isTrue);
      expect(isExpanded, isFalse);
      expect(isDesktopNav, isFalse);

      // Change to desktop (1280x800)
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMedium = context.isMedium;
              isExpanded = context.isExpanded;
              isDesktopNav = context.isDesktopNav;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isCompact, isFalse);
      expect(isMedium, isFalse);
      expect(isExpanded, isTrue);
      expect(isDesktopNav, isTrue);
    });
  });

  group('PlayerDock & NowPlayingSheet Responsive Tests', () {
    testWidgets('Compact mode renders mini-player dock and opens NowPlayingSheet on tap', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late MerlinAudioHandler audioHandler;
      await tester.runAsync(() async {
        audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
        final ep = const Episode(
          id: 1,
          podcastId: 1,
          podcastRss: 'https://example.com/rss.xml',
          guid: 'ep-dock-mobile',
          title: 'Mobile Mini Player Test Episode with a Long Title to Check Truncation',
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
        buildAppWithViewport(
          child: const Scaffold(
            bottomNavigationBar: PlayerDock(),
          ),
          size: const Size(360, 640),
          audioHandler: audioHandler,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull, reason: 'Mini player should not throw RenderFlex overflow');

      // Title should be visible
      expect(find.textContaining('Mobile Mini Player'), findsOneWidget);
      // Play/pause button present
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      // Expand arrow present
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

      // Desktop controls (speed, sleep timer) are not crammed on the mini player row
      expect(find.byIcon(Icons.speed), findsNothing);
      expect(find.byIcon(Icons.bedtime_outlined), findsNothing);

      // Tap on mini player to open NowPlayingSheet
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NowPlayingSheet), findsOneWidget);
      expect(find.text('Podcast Merlin'), findsWidgets);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      // Full controls now available in sheet
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      expect(find.byIcon(Icons.queue_music), findsOneWidget);

      // Close sheet
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingSheet), findsNothing);
    });

    testWidgets('Desktop mode renders full desktop dock with all controls', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late MerlinAudioHandler audioHandler;
      await tester.runAsync(() async {
        audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
        final ep = const Episode(
          id: 2,
          podcastId: 1,
          podcastRss: 'https://example.com/rss.xml',
          guid: 'ep-dock-desktop',
          title: 'Desktop Player Episode',
          description: '',
          mediaUrl: 'https://example.com/test2.mp3',
          duration: 2400,
          position: 600,
          imageUrl: '',
        );
        await audioHandler.playEpisode(ep);
      });
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const Scaffold(
            bottomNavigationBar: PlayerDock(),
          ),
          size: const Size(1280, 800),
          audioHandler: audioHandler,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      expect(find.byIcon(Icons.queue_music), findsOneWidget);
    });
  });

  group('EpisodeListView Responsive Layout Tests', () {
    testWidgets('EpisodeListView renders on compact phone (360x640) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final podcast = const Podcast(
        id: 10,
        title: 'Very Long Podcast Show Title For Responsive Testing Purposes',
        rssUrl: 'https://example.com/feed.xml',
        description: 'Testing show description',
        imageUrl: '',
        link: 'https://example.com',
      );

      final episodes = <Episode>[
        Episode(
          id: 101,
          podcastId: 10,
          podcastRss: podcast.rssUrl,
          guid: 'ep-101',
          title: 'Episode 101: Extremely Long Episode Title That Used to Cause RenderFlex Overflow on Mobile Screens',
          description: 'Episode notes description here',
          mediaUrl: 'https://example.com/101.mp3',
          duration: 3665,
          position: 1200,
          imageUrl: '',
          publishedAt: DateTime(2026, 3, 15),
          isPlayed: true,
          isStarred: true,
        ),
        Episode(
          id: 102,
          podcastId: 10,
          podcastRss: podcast.rssUrl,
          guid: 'ep-102',
          title: 'Episode 102: Short Title',
          description: '',
          mediaUrl: 'https://example.com/102.mp3',
          duration: 1800,
          position: 0,
          imageUrl: '',
          publishedAt: DateTime(2026, 3, 10),
        ),
      ];

      await tester.runAsync(() async {
        await db.insertOrUpdatePodcast(podcast);
        await db.insertEpisodes(episodes);
      });

      await tester.pumpWidget(
        buildAppWithViewport(
          child: EpisodeListView(podcast: podcast),
          size: const Size(360, 640),
          extraOverrides: [
            episodesNotifierProvider(podcast.id!).overrideWith(
              (ref) => TestEpisodesNotifier(episodes),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull, reason: 'EpisodeListView must not throw RenderFlex overflow on 360px width');

      // Verify filter chips and search field are visible
      expect(find.byKey(const ValueKey('filter_all')), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify episode titles and played badge are rendered
      expect(find.textContaining('Episode 101: Extremely Long'), findsOneWidget);
      expect(find.text('Played • '), findsOneWidget);
    });
  });

  group('SettingsView Responsive Layout Tests', () {
    testWidgets('SettingsView stacks dropdowns and OPML buttons on compact screen (360x640)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const SettingsView(),
          size: const Size(360, 640),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'SettingsView must not throw RenderFlex overflow on 360px width');
      expect(find.text('Rewind Interval'), findsOneWidget);
      expect(find.text('Fast Forward Interval'), findsOneWidget);
      expect(find.text('Export OPML'), findsOneWidget);
      expect(find.text('Import OPML'), findsOneWidget);
      expect(find.text('Open Download Center'), findsOneWidget);
    });
  });

  group('PodcastCatalogView Responsive Layout Tests', () {
    testWidgets('PodcastCatalogView renders 2 columns on 360px width without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const PodcastCatalogView(),
          size: const Size(360, 640),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'PodcastCatalogView must not throw overflow on 360px width');
      expect(find.text('Podcast Merlin'), findsOneWidget);
    });
  });

  group('DownloadCenterView Responsive Layout Tests', () {
    testWidgets('DownloadCenterView renders on 360px width without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const DownloadCenterView(),
          size: const Size(360, 640),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'DownloadCenterView must not throw overflow on 360px width');
      expect(find.text('Download Center'), findsOneWidget);
      expect(find.text('Queue & Active'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });
  });

  group('MainShell NavigationBar & NavigationRail Tests', () {
    testWidgets('MainShell renders NavigationBar on compact width (360x640)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const MainShell(),
          size: const Size(360, 640),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('MainShell renders NavigationRail on desktop width (1280x800)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const MainShell(),
          size: const Size(1280, 800),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('Extreme Viewport & Orientation Tests', () {
    testWidgets('MainShell renders on extreme narrow viewport (320x568) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late MerlinAudioHandler audioHandler;
      await tester.runAsync(() async {
        audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
        final ep = const Episode(
          id: 50,
          podcastId: 1,
          podcastRss: 'https://example.com/rss.xml',
          guid: 'ep-se-shell',
          title: 'Narrow Viewport Episode Title',
          description: '',
          mediaUrl: 'https://example.com/se.mp3',
          duration: 1800,
          position: 120,
          imageUrl: '',
        );
        await audioHandler.playEpisode(ep);
      });
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const MainShell(),
          size: const Size(320, 568),
          audioHandler: audioHandler,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull, reason: 'MainShell must not throw RenderFlex overflow on 320x568');
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(PlayerDock), findsOneWidget);
    });

    testWidgets('PlayerDock compact mini-player renders on 320x568 with min 48x48 hit targets, full tap area coverage, and zero overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late MerlinAudioHandler audioHandler;
      await tester.runAsync(() async {
        audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
        final ep = const Episode(
          id: 51,
          podcastId: 1,
          podcastRss: 'https://example.com/rss.xml',
          guid: 'ep-se-dock',
          title: 'Narrow Phone Mini Player Very Long Title Checking Hit Targets',
          description: '',
          mediaUrl: 'https://example.com/se_dock.mp3',
          duration: 2400,
          position: 400,
          imageUrl: '',
        );
        await audioHandler.playEpisode(ep);
      });
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: const Scaffold(
            bottomNavigationBar: PlayerDock(),
          ),
          size: const Size(320, 568),
          audioHandler: audioHandler,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull, reason: 'PlayerDock must not throw RenderFlex overflow on 320x568');

      // Verify minimum 48x48 hit targets for Play/Pause, Fast Forward, and Expand chevron
      final playBtn = find.ancestor(
        of: find.byIcon(Icons.pause_circle_filled),
        matching: find.byType(IconButton),
      );
      final playSize = tester.getSize(playBtn);
      expect(playSize.width, greaterThanOrEqualTo(48.0));
      expect(playSize.height, greaterThanOrEqualTo(48.0));

      final forwardBtn = find.ancestor(
        of: find.byTooltip('Forward 30s'),
        matching: find.byType(IconButton),
      );
      final forwardSize = tester.getSize(forwardBtn);
      expect(forwardSize.width, greaterThanOrEqualTo(48.0));
      expect(forwardSize.height, greaterThanOrEqualTo(48.0));

      final expandBtn = find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_up),
        matching: find.byType(IconButton),
      );
      final expandSize = tester.getSize(expandBtn);
      expect(expandSize.width, greaterThanOrEqualTo(48.0));
      expect(expandSize.height, greaterThanOrEqualTo(48.0));

      // Verify full tap area coverage: tapping the title text on mini-player opens NowPlayingSheet
      await tester.tap(find.textContaining('Narrow Phone Mini Player'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final nowPlayingSheet = find.byType(NowPlayingSheet);
      expect(nowPlayingSheet, findsOneWidget);

      // Verify NowPlayingSheet control cluster touch targets are at least 48x48
      final rewindSheetBtn = find.descendant(
        of: nowPlayingSheet,
        matching: find.byTooltip('Rewind 10s'),
      );
      final rewindSize = tester.getSize(find.ancestor(of: rewindSheetBtn, matching: find.byType(IconButton)));
      expect(rewindSize.width, greaterThanOrEqualTo(48.0));
      expect(rewindSize.height, greaterThanOrEqualTo(48.0));

      final playSheetBtn = find.descendant(
        of: nowPlayingSheet,
        matching: find.byIcon(Icons.pause_circle_filled),
      );
      final playSheetSize = tester.getSize(find.ancestor(of: playSheetBtn, matching: find.byType(IconButton)));
      expect(playSheetSize.width, greaterThanOrEqualTo(48.0));
      expect(playSheetSize.height, greaterThanOrEqualTo(48.0));

      final forwardSheetBtn = find.descendant(
        of: nowPlayingSheet,
        matching: find.byTooltip('Fast forward 30s'),
      );
      final forwardSheetSize = tester.getSize(find.ancestor(of: forwardSheetBtn, matching: find.byType(IconButton)));
      expect(forwardSheetSize.width, greaterThanOrEqualTo(48.0));
      expect(forwardSheetSize.height, greaterThanOrEqualTo(48.0));

      final speedBtn = find.descendant(
        of: nowPlayingSheet,
        matching: find.byTooltip('Playback Speed'),
      );
      final speedSize = tester.getSize(find.ancestor(of: speedBtn, matching: find.byType(IconButton)));
      expect(speedSize.width, greaterThanOrEqualTo(48.0));
      expect(speedSize.height, greaterThanOrEqualTo(48.0));

      final sleepBtn = find.descendant(
        of: nowPlayingSheet,
        matching: find.byTooltip('Sleep Timer'),
      );
      final sleepSize = tester.getSize(find.ancestor(of: sleepBtn, matching: find.byType(IconButton)));
      expect(sleepSize.width, greaterThanOrEqualTo(48.0));
      expect(sleepSize.height, greaterThanOrEqualTo(48.0));

      final queueBtn = find.descendant(
        of: nowPlayingSheet,
        matching: find.byTooltip('Up Next Queue'),
      );
      final queueSize = tester.getSize(find.ancestor(of: queueBtn, matching: find.byType(IconButton)));
      expect(queueSize.width, greaterThanOrEqualTo(48.0));
      expect(queueSize.height, greaterThanOrEqualTo(48.0));

      final closeBtn = find.descendant(
        of: nowPlayingSheet,
        matching: find.byTooltip('Close Player'),
      );
      final closeSize = tester.getSize(find.ancestor(of: closeBtn, matching: find.byType(IconButton)));
      expect(closeSize.width, greaterThanOrEqualTo(48.0));
      expect(closeSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('EpisodeListView renders on extreme narrow viewport (320x568) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final podcast = const Podcast(
        id: 20,
        title: 'Narrow Podcast Show Title Testing Extreme Overflow Cases',
        rssUrl: 'https://example.com/narrow_feed.xml',
        description: 'Testing show description in narrow viewport mode',
        imageUrl: '',
        link: 'https://example.com/narrow',
      );

      final episodes = <Episode>[
        Episode(
          id: 201,
          podcastId: 20,
          podcastRss: podcast.rssUrl,
          guid: 'ep-201',
          title: 'Episode 201: Extremely Long Episode Title in Narrow Screen Testing Ellipsis and Wrapping Without Overflow',
          description: 'Episode notes description here',
          mediaUrl: 'https://example.com/201.mp3',
          duration: 4500,
          position: 1500,
          imageUrl: '',
          publishedAt: DateTime(2026, 4, 1),
          isPlayed: true,
          isStarred: true,
          downloadedBytes: 15 * 1024 * 1024,
        ),
        Episode(
          id: 202,
          podcastId: 20,
          podcastRss: podcast.rssUrl,
          guid: 'ep-202',
          title: 'Episode 202: Downloading Episode Status',
          description: 'Description 202',
          mediaUrl: 'https://example.com/202.mp3',
          duration: 2100,
          position: 0,
          imageUrl: '',
          publishedAt: DateTime(2026, 4, 2),
        ),
      ];

      await tester.runAsync(() async {
        await db.insertOrUpdatePodcast(podcast);
        await db.insertEpisodes(episodes);
      });

      await tester.pumpWidget(
        buildAppWithViewport(
          child: EpisodeListView(podcast: podcast),
          size: const Size(320, 568),
          extraOverrides: [
            episodesNotifierProvider(podcast.id!).overrideWith(
              (ref) => TestEpisodesNotifier(episodes),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull, reason: 'EpisodeListView must not throw RenderFlex overflow on 320x568');
      expect(find.byKey(const ValueKey('filter_all')), findsOneWidget);
      expect(find.textContaining('Episode 201: Extremely Long'), findsOneWidget);
    });

    testWidgets('PlaybackSpeedSheet renders on mobile landscape (640x360) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => PlaybackSpeedSheet.show(context),
                  child: const Text('Show Speed Sheet'),
                ),
              ),
            ),
          ),
          size: const Size(640, 360),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Show Speed Sheet'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'PlaybackSpeedSheet must not throw RenderFlex overflow on 640x360');
      expect(find.byType(PlaybackSpeedSheet), findsOneWidget);
      expect(find.text('Playback Speed'), findsOneWidget);
      expect(find.text('QUICK PRESETS'), findsOneWidget);
    });

    testWidgets('SleepTimerBottomSheet renders on mobile landscape (640x360) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SleepTimerBottomSheet.show(context),
                  child: const Text('Show Sleep Sheet'),
                ),
              ),
            ),
          ),
          size: const Size(640, 360),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Show Sleep Sheet'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'SleepTimerBottomSheet must not throw RenderFlex overflow on 640x360');
      expect(find.byType(SleepTimerBottomSheet), findsOneWidget);
      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(find.text('30 minutes'), findsOneWidget);
      expect(find.text('End of Current Episode'), findsOneWidget);
    });

    testWidgets('QueueBottomSheet renders on mobile landscape (640x360) and respects safe area with zero overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 34, left: 16, right: 16);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
      });

      late MerlinAudioHandler audioHandler;
      await tester.runAsync(() async {
        final podcast = const Podcast(
          id: 30,
          title: 'Queue Test Podcast',
          rssUrl: 'https://example.com/rss.xml',
          description: '',
          imageUrl: '',
          link: '',
        );
        await db.insertOrUpdatePodcast(podcast);
        final ep1 = const Episode(
          id: 301,
          podcastId: 30,
          podcastRss: 'https://example.com/rss.xml',
          guid: 'ep-queue-1',
          title: 'Queue Test Episode in Landscape',
          description: '',
          mediaUrl: 'https://example.com/q1.mp3',
          duration: 1200,
          position: 100,
          imageUrl: '',
        );
        final ep2 = const Episode(
          id: 302,
          podcastId: 30,
          podcastRss: 'https://example.com/rss.xml',
          guid: 'ep-queue-2',
          title: 'Second Queue Item',
          description: '',
          mediaUrl: 'https://example.com/q2.mp3',
          duration: 1500,
          position: 0,
          imageUrl: '',
        );
        await db.insertEpisodes([ep1, ep2]);
        audioHandler = MerlinAudioHandler(db: db, urlLoader: (_) async {});
        await audioHandler.playEpisode(ep1);
        await audioHandler.addToQueue(ep2);
      });
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        buildAppWithViewport(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => QueueBottomSheet.show(context),
                  child: const Text('Show Queue Sheet'),
                ),
              ),
            ),
          ),
          size: const Size(640, 360),
          audioHandler: audioHandler,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Show Queue Sheet'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'QueueBottomSheet must not throw overflow on 640x360 with bottom insets');
      expect(find.byType(QueueBottomSheet), findsOneWidget);
      expect(find.text('Up Next Queue'), findsOneWidget);
      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.text('UP NEXT (1)'), findsOneWidget);
      expect(find.text('Clear Queue'), findsOneWidget);
    });
  });
}
