import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/models/search_result_podcast.dart';
import 'podcast_search_provider.dart';

class ITunesSearchProvider implements PodcastSearchProvider {
  final Dio _dio;

  ITunesSearchProvider({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://itunes.apple.com'));

  @override
  String get id => 'itunes';

  @override
  String get displayName => 'Apple Podcasts / iTunes';

  @override
  bool get requiresCredentials => false;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<List<SearchResultPodcast>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getTrending();

    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'term': trimmed,
          'entity': 'podcast',
          'limit': 25,
        },
      );

      return _parseResponse(response.data);
    } catch (e) {
      throw Exception('iTunes search failed: $e');
    }
  }

  @override
  Future<List<SearchResultPodcast>> getTrending() async {
    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'term': 'podcast',
          'entity': 'podcast',
          'limit': 25,
        },
      );

      return _parseResponse(response.data);
    } catch (e) {
      return [];
    }
  }

  List<SearchResultPodcast> _parseResponse(dynamic data) {
    if (data == null) return [];
    final jsonMap = data is String ? jsonDecode(data) : data;
    if (jsonMap is! Map) return [];

    final results = jsonMap['results'];
    if (results is! List) return [];

    final list = <SearchResultPodcast>[];
    for (final item in results) {
      if (item is Map<String, dynamic>) {
        final feedUrl = (item['feedUrl'] ?? '').toString();
        if (feedUrl.isEmpty) continue;

        final genre = item['primaryGenreName']?.toString();

        list.add(
          SearchResultPodcast(
            title: (item['trackName'] ?? item['collectionName'] ?? 'Untitled Podcast').toString(),
            author: (item['artistName'] ?? '').toString(),
            rssUrl: feedUrl,
            imageUrl: (item['artworkUrl600'] ?? item['artworkUrl100'] ?? '').toString(),
            description: (item['collectionName'] ?? '').toString(),
            websiteUrl: (item['collectionViewUrl'] ?? '').toString(),
            categories: genre != null ? [genre] : [],
            episodeCount: item['trackCount'] as int?,
            providerId: id,
          ),
        );
      }
    }
    return list;
  }
}
