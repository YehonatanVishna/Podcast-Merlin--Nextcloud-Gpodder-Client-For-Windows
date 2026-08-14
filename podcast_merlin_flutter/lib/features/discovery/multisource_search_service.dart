import '../../core/models/search_result_podcast.dart';
import 'itunes_provider.dart';
import 'podcast_index_provider.dart';
import 'podcast_search_provider.dart';

class MultisourceSearchService {
  final Map<String, PodcastSearchProvider> _providers = {};
  String _activeProviderId = 'itunes';

  MultisourceSearchService({
    PodcastSearchProvider? initialProvider,
  }) {
    // Register default providers
    registerProvider(ITunesSearchProvider());
    registerProvider(PodcastIndexProvider());

    if (initialProvider != null) {
      registerProvider(initialProvider);
      _activeProviderId = initialProvider.id;
    } else {
      _activeProviderId = 'itunes';
    }
  }

  void registerProvider(PodcastSearchProvider provider) {
    _providers[provider.id] = provider;
  }

  List<PodcastSearchProvider> get availableProviders => _providers.values.toList();

  String get activeProviderId => _activeProviderId;

  PodcastSearchProvider get activeProvider {
    return _providers[_activeProviderId] ?? _providers.values.first;
  }

  void setActiveProvider(String providerId) {
    if (_providers.containsKey(providerId)) {
      _activeProviderId = providerId;
    }
  }

  Future<List<SearchResultPodcast>> search(String query) async {
    final provider = activeProvider;
    return await provider.search(query);
  }

  Future<List<SearchResultPodcast>> getTrending() async {
    final provider = activeProvider;
    return await provider.getTrending();
  }
}
