import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/models/search_result_podcast.dart';
import 'package:podcast_merlin_flutter/features/discovery/multisource_search_service.dart';
import 'package:podcast_merlin_flutter/features/discovery/podcast_search_provider.dart';

class MockSearchProvider implements PodcastSearchProvider {
  final String _id;
  final String _displayName;

  MockSearchProvider(this._id, this._displayName);

  @override
  String get id => _id;

  @override
  String get displayName => _displayName;

  @override
  bool get requiresCredentials => false;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<List<SearchResultPodcast>> search(String query) async {
    return [
      SearchResultPodcast(
        title: 'Result from $_displayName for "$query"',
        author: 'Mock Author',
        rssUrl: 'https://example.com/$_id/feed.xml',
        imageUrl: 'https://example.com/$_id/image.png',
        description: 'Mock Description',
        websiteUrl: 'https://example.com',
        providerId: _id,
      )
    ];
  }

  @override
  Future<List<SearchResultPodcast>> getTrending() async {
    return [
      SearchResultPodcast(
        title: 'Trending from $_displayName',
        author: 'Mock Author',
        rssUrl: 'https://example.com/$_id/trending.xml',
        imageUrl: 'https://example.com/$_id/trending.png',
        description: 'Mock Trending Description',
        websiteUrl: 'https://example.com',
        providerId: _id,
      )
    ];
  }
}

void main() {
  group('MultisourceSearchService Tests', () {
    test('initializes with default providers and supports adding custom providers', () {
      final p1 = MockSearchProvider('custom_provider', 'Custom Provider');
      final service = MultisourceSearchService(initialProvider: p1);

      expect(service.availableProviders.length, greaterThanOrEqualTo(2));
      expect(service.activeProviderId, 'custom_provider');

      final p2 = MockSearchProvider('another_provider', 'Another Provider');
      service.registerProvider(p2);

      expect(service.availableProviders.length, greaterThanOrEqualTo(3));
    });

    test('switches active provider correctly', () async {
      final p1 = MockSearchProvider('podcast_index', 'Podcast Index');
      final p2 = MockSearchProvider('itunes', 'iTunes');

      final service = MultisourceSearchService(initialProvider: p1);
      service.registerProvider(p2);

      expect(service.activeProvider.displayName, 'Podcast Index');

      service.setActiveProvider('itunes');
      expect(service.activeProvider.displayName, 'iTunes');

      final results = await service.search('flutter');
      expect(results.first.title, contains('iTunes'));
      expect(results.first.providerId, 'itunes');
    });

    test('getTrending delegates to active provider', () async {
      final p1 = MockSearchProvider('podcast_index', 'Podcast Index');
      final service = MultisourceSearchService(initialProvider: p1);

      final trending = await service.getTrending();
      expect(trending.length, 1);
      expect(trending.first.title, 'Trending from Podcast Index');
    });
  });
}
