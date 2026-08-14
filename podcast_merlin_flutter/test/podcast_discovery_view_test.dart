import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/models/search_result_podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/discovery/multisource_search_service.dart';
import 'package:podcast_merlin_flutter/features/discovery/podcast_search_provider.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/podcast_discovery_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestSearchProvider implements PodcastSearchProvider {
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
        title: 'Trending Merlin Show',
        author: 'Merlin Team',
        rssUrl: 'https://example.com/trending_merlin.xml',
        imageUrl: '',
        description: 'Popular tech show',
        websiteUrl: 'https://example.com',
        providerId: 'itunes',
      ),
    ];
  }

  @override
  Future<List<SearchResultPodcast>> search(String query) async {
    return [
      SearchResultPodcast(
        title: 'Found Show for $query',
        author: 'Search Author',
        rssUrl: 'https://example.com/$query.xml',
        imageUrl: '',
        description: 'Searched description',
        websiteUrl: 'https://example.com',
        providerId: 'itunes',
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('PodcastDiscoveryView Widget Tests', () {
    late MerlinAudioHandler audioHandler;

    setUp(() {
      audioHandler = MerlinAudioHandler();
    });

    tearDown(() async {
      await audioHandler.stop();
    });

    testWidgets('renders search bar and trending list', (tester) async {
      final mockService = MultisourceSearchService(initialProvider: TestSearchProvider());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(audioHandler),
            multisourceSearchServiceProvider.overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: PodcastDiscoveryView(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Discover Podcasts'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('🔥 Trending Podcasts'), findsOneWidget);
      expect(find.text('Trending Merlin Show'), findsOneWidget);
    });

    testWidgets('typing search query updates search results', (tester) async {
      final mockService = MultisourceSearchService(initialProvider: TestSearchProvider());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(audioHandler),
            multisourceSearchServiceProvider.overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: PodcastDiscoveryView(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Flutter');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Found Show for Flutter'), findsOneWidget);
    });
  });
}
