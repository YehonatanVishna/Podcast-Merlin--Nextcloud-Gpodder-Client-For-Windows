import '../../core/models/search_result_podcast.dart';

abstract class PodcastSearchProvider {
  String get id;
  String get displayName;
  bool get requiresCredentials;
  Future<bool> isConfigured();
  Future<List<SearchResultPodcast>> search(String query);
  Future<List<SearchResultPodcast>> getTrending();
}
