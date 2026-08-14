import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/features/discovery/podcast_index_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PodcastIndexProvider Tests', () {
    late PodcastIndexProvider provider;

    setUp(() {
      provider = PodcastIndexProvider();
    });

    test('generateAuthHeaders computes correct SHA-1 signature and header structure', () {
      const apiKey = 'TEST_KEY_123';
      const apiSecret = 'TEST_SECRET_456';
      const timestamp = 1700000000;

      final headers = provider.generateAuthHeaders(apiKey, apiSecret, timestamp);

      expect(headers['User-Agent'], 'PodcastMerlin/1.0');
      expect(headers['X-Auth-Key'], apiKey);
      expect(headers['X-Auth-Date'], '1700000000');

      // Expected SHA1 hash of "TEST_KEY_123TEST_SECRET_4561700000000"
      final expectedData = '$apiKey$apiSecret$timestamp';
      final expectedHash = sha1.convert(utf8.encode(expectedData)).toString();

      expect(headers['Authorization'], expectedHash);
    });

    test('search parses JSON response feeds into SearchResultPodcast objects', () async {
      final mockDio = Dio();
      mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
        if (options.path.contains('/search/byterm')) {
          final jsonResponse = {
            'status': 'true',
            'feeds': [
              {
                'id': 101,
                'title': 'Merlin Tech Podcast',
                'url': 'https://example.com/rss.xml',
                'image': 'https://example.com/cover.png',
                'description': 'A podcast about coding',
                'author': 'Merlin Team',
                'link': 'https://example.com',
                'categories': {'1': 'Technology', '2': 'Software'},
                'episodeCount': 42,
                'language': 'en',
              }
            ]
          };
          return ResponseBody.fromString(
            jsonEncode(jsonResponse),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('Not Found', 404);
      });

      final customProvider = PodcastIndexProvider(dio: mockDio);
      final results = await customProvider.search('Merlin');

      expect(results.length, 1);
      final pod = results.first;
      expect(pod.title, 'Merlin Tech Podcast');
      expect(pod.rssUrl, 'https://example.com/rss.xml');
      expect(pod.imageUrl, 'https://example.com/cover.png');
      expect(pod.author, 'Merlin Team');
      expect(pod.categories, contains('Technology'));
      expect(pod.episodeCount, 42);
      expect(pod.providerId, 'podcast_index');
    });

    test('getTrending parses JSON response feeds correctly', () async {
      final mockDio = Dio();
      mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
        if (options.path.contains('/podcasts/trending')) {
          final jsonResponse = {
            'status': 'true',
            'feeds': [
              {
                'id': 202,
                'title': 'Trending Daily',
                'url': 'https://example.com/trending.xml',
                'image': 'https://example.com/trending.png',
                'description': 'Trending news',
                'author': 'Daily News',
                'link': 'https://example.com/news',
              }
            ]
          };
          return ResponseBody.fromString(
            jsonEncode(jsonResponse),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('Not Found', 404);
      });

      final customProvider = PodcastIndexProvider(dio: mockDio);
      final results = await customProvider.getTrending();

      expect(results.length, 1);
      expect(results.first.title, 'Trending Daily');
      expect(results.first.rssUrl, 'https://example.com/trending.xml');
    });

    test('returns empty list when API returns non-200 or error', () async {
      final mockDio = Dio();
      mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
        return ResponseBody.fromString('Internal Server Error', 500);
      });

      final customProvider = PodcastIndexProvider(dio: mockDio);
      final results = await customProvider.search('error test');

      expect(results, isEmpty);
    });
  });
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) _handler;
  _MockHttpClientAdapter(this._handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
