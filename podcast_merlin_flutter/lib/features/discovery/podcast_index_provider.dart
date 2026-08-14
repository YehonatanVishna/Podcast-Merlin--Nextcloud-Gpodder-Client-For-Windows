import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../../core/models/search_result_podcast.dart';
import '../sync/secure_storage_service.dart';
import 'podcast_search_provider.dart';

class PodcastIndexProvider implements PodcastSearchProvider {
  final SecureStorageService _storage;
  final Dio _dio;

  // Default credentials
  static const String defaultApiKey = 'X5T6K6Z8J6X9R8V6W9Y2';
  static const String defaultApiSecret = 'b6m8d4v3n6p7q2w9x8y1z5c3v9b2n4m8';

  PodcastIndexProvider({
    SecureStorageService? storage,
    Dio? dio,
  })  : _storage = storage ?? SecureStorageService(),
        _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://api.podcastindex.org/api/1.0'));

  @override
  String get id => 'podcast_index';

  @override
  String get displayName => 'Podcast Index';

  @override
  bool get requiresCredentials => true;

  Future<Map<String, String>> _getCredentials() async {
    final customKey = await _storage.read(SecureStorageService.keyPodcastIndexApiKey);
    final customSecret = await _storage.read(SecureStorageService.keyPodcastIndexApiSecret);

    final apiKey = (customKey != null && customKey.trim().isNotEmpty)
        ? customKey.trim()
        : defaultApiKey;
    final apiSecret = (customSecret != null && customSecret.trim().isNotEmpty)
        ? customSecret.trim()
        : defaultApiSecret;

    return {'apiKey': apiKey, 'apiSecret': apiSecret};
  }

  @override
  Future<bool> isConfigured() async {
    final creds = await _getCredentials();
    return creds['apiKey']!.isNotEmpty && creds['apiSecret']!.isNotEmpty;
  }

  Map<String, String> generateAuthHeaders(String apiKey, String apiSecret, [int? customTimestamp]) {
    final apiHeaderTime = customTimestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final timeStr = apiHeaderTime.toString();
    final data4Hash = apiKey + apiSecret + timeStr;
    final authorization = sha1.convert(utf8.encode(data4Hash)).toString();

    return {
      'User-Agent': 'PodcastMerlin/1.0',
      'X-Auth-Key': apiKey,
      'X-Auth-Date': timeStr,
      'Authorization': authorization,
    };
  }

  @override
  Future<List<SearchResultPodcast>> search(String query) async {
    final creds = await _getCredentials();
    final headers = generateAuthHeaders(creds['apiKey']!, creds['apiSecret']!);

    try {
      final response = await _dio.get(
        '/search/byterm',
        queryParameters: {'q': query.trim()},
        options: Options(headers: headers),
      );

      return _parseFeedList(response.data);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        throw Exception('Podcast Index returned 401 Unauthorized. Please enter your API Key & Secret in Settings or switch to Apple Podcasts.');
      }
      return [];
    }
  }

  @override
  Future<List<SearchResultPodcast>> getTrending() async {
    final creds = await _getCredentials();
    final headers = generateAuthHeaders(creds['apiKey']!, creds['apiSecret']!);

    try {
      final response = await _dio.get(
        '/podcasts/trending',
        queryParameters: {'max': 20},
        options: Options(headers: headers),
      );

      return _parseFeedList(response.data);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        throw Exception('Podcast Index returned 401 Unauthorized. Please enter your API Key & Secret in Settings or switch to Apple Podcasts.');
      }
      return [];
    }
  }

  List<SearchResultPodcast> _parseFeedList(dynamic data) {
    if (data == null) return [];
    final jsonMap = data is String ? jsonDecode(data) : data;
    if (jsonMap is! Map) return [];

    final feeds = jsonMap['feeds'];
    if (feeds is! List) return [];

    return feeds
        .whereType<Map<String, dynamic>>()
        .map((f) => SearchResultPodcast.fromPodcastIndexJson(f))
        .toList();
  }
}
