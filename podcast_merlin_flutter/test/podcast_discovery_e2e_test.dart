import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/models/search_result_podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/discovery/multisource_search_service.dart';
import 'package:podcast_merlin_flutter/features/discovery/podcast_search_provider.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
import 'package:podcast_merlin_flutter/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class E2EHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

class TestPodcastsNotifier extends PodcastsNotifier {
  final List<Podcast> _list = [];

  TestPodcastsNotifier(super.db, super.syncStatusNotifier) {
    state = AsyncValue.data(_list);
  }

  @override
  Future<void> loadPodcasts() async {
    state = AsyncValue.data(List.from(_list));
  }

  @override
  Future<bool> addPodcastFeed(String rssUrl) async {
    final podcast = Podcast(
      rssUrl: rssUrl,
      title: 'E2E Discovered Podcast',
      imageUrl: '',
      description: 'Discovered via Podcast Index',
      link: 'https://example.com',
    );
    _list.add(podcast);
    state = AsyncValue.data(List.from(_list));
    return true;
  }
}

class MockE2ESearchProvider implements PodcastSearchProvider {
  @override
  String get id => 'itunes';

  @override
  String get displayName => 'iTunes';

  @override
  bool get requiresCredentials => false;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<List<SearchResultPodcast>> getTrending() async {
    return [
      const SearchResultPodcast(
        title: 'E2E Discovered Podcast',
        author: 'E2E Author',
        rssUrl: 'https://example.com/e2e_feed.xml',
        imageUrl: '',
        description: 'Discovered via iTunes',
        websiteUrl: 'https://example.com',
        providerId: 'itunes',
      ),
    ];
  }

  @override
  Future<List<SearchResultPodcast>> search(String query) async {
    return getTrending();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = E2EHttpOverrides();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Podcast Discovery End-to-End Integration Test', () {
    late DatabaseHelper dbHelper;
    late MerlinAudioHandler audioHandler;

    setUp(() async {
      dbHelper = DatabaseHelper.instance;
      await dbHelper.database;
      audioHandler = MerlinAudioHandler();
    });

    tearDown(() async {
      await audioHandler.stop();
    });

    testWidgets('full flow: Discover podcast -> Subscribe -> Appears in Catalog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MultisourceSearchService(initialProvider: MockE2ESearchProvider());
      final mockSyncService = SyncService(
        apiClient: GPodderApiClient(),
        storage: SecureStorageService(),
        db: dbHelper,
      );
      final mockSyncStatusNotifier = SyncStatusNotifier(mockSyncService);
      final testPodcastsNotifier = TestPodcastsNotifier(dbHelper, mockSyncStatusNotifier);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(dbHelper),
            audioHandlerProvider.overrideWithValue(audioHandler),
            multisourceSearchServiceProvider.overrideWithValue(mockService),
            podcastsNotifierProvider.overrideWith((ref) => testPodcastsNotifier),
          ],
          child: const PodcastMerlinApp(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Tap on "Discover" tab in NavigationRail using icon
      final discoverTabIcon = find.byIcon(Icons.explore_outlined);
      expect(discoverTabIcon, findsOneWidget);
      await tester.tap(discoverTabIcon);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify discovered podcast card is rendered
      expect(find.text('E2E Discovered Podcast'), findsOneWidget);

      // Tap on Subscribe button
      final subscribeBtn = find.widgetWithText(ElevatedButton, 'Subscribe');
      expect(subscribeBtn, findsOneWidget);
      await tester.tap(subscribeBtn);

      await tester.pump(const Duration(milliseconds: 300));

      // Navigate back to Catalog tab using icon
      final catalogTabIcon = find.byIcon(Icons.podcasts_outlined);
      await tester.tap(catalogTabIcon);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify podcast now appears in Catalog
      expect(find.text('E2E Discovered Podcast'), findsOneWidget);
    });
  });
}
