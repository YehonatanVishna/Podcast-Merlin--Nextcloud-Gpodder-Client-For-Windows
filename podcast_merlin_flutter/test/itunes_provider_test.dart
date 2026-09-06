import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/features/discovery/itunes_provider.dart';

void main() {
  group('ITunesSearchProvider Tests', () {
    test('search parses JSON response feeds into SearchResultPodcast objects', () async {
      final mockDio = Dio(BaseOptions(baseUrl: 'https://itunes.apple.com'));
      mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
        if (options.path.contains('/search')) {
          final jsonResponse = {
            'resultCount': 1,
            'results': [
              {
                'trackName': 'Tech Talk',
                'artistName': 'John Doe',
                'feedUrl': 'https://example.com/tech.xml',
                'artworkUrl600': 'https://example.com/cover.jpg',
                'collectionName': 'A great tech show',
                'collectionViewUrl': 'https://example.com/show',
                'primaryGenreName': 'Technology',
                'trackCount': 42
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

      final provider = ITunesSearchProvider(dio: mockDio);
      final results = await provider.search('tech');

      expect(results.length, equals(1));
      final pod = results.first;
      expect(pod.title, equals('Tech Talk'));
      expect(pod.author, equals('John Doe'));
      expect(pod.rssUrl, equals('https://example.com/tech.xml'));
      expect(pod.imageUrl, equals('https://example.com/cover.jpg'));
      expect(pod.categories, contains('Technology'));
      expect(pod.episodeCount, equals(42));
      expect(pod.providerId, equals('itunes'));
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
