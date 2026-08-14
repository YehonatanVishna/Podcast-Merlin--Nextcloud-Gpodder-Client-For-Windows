import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/search_result_podcast.dart';
import 'multisource_search_service.dart';

class DiscoveryState {
  final List<SearchResultPodcast> results;
  final bool isLoading;
  final String? error;
  final String currentQuery;
  final String activeProviderId;
  final bool isTrending;

  const DiscoveryState({
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.currentQuery = '',
    this.activeProviderId = 'podcast_index',
    this.isTrending = true,
  });

  DiscoveryState copyWith({
    List<SearchResultPodcast>? results,
    bool? isLoading,
    String? error,
    String? currentQuery,
    String? activeProviderId,
    bool? isTrending,
  }) {
    return DiscoveryState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentQuery: currentQuery ?? this.currentQuery,
      activeProviderId: activeProviderId ?? this.activeProviderId,
      isTrending: isTrending ?? this.isTrending,
    );
  }
}

class DiscoveryNotifier extends StateNotifier<DiscoveryState> {
  final MultisourceSearchService _searchService;

  DiscoveryNotifier(this._searchService) : super(const DiscoveryState()) {
    loadTrending();
  }

  Future<void> loadTrending() async {
    state = state.copyWith(isLoading: true, error: null, currentQuery: '', isTrending: true);
    try {
      final results = await _searchService.getTrending();
      if (mounted) {
        state = state.copyWith(
          results: results,
          isLoading: false,
          isTrending: true,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load trending podcasts: $e',
        );
      }
    }
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return loadTrending();
    }

    state = state.copyWith(isLoading: true, error: null, currentQuery: trimmed, isTrending: false);
    try {
      final results = await _searchService.search(trimmed);
      if (mounted) {
        state = state.copyWith(
          results: results,
          isLoading: false,
          isTrending: false,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isLoading: false,
          error: 'Search failed: $e',
        );
      }
    }
  }

  void setActiveProvider(String providerId) {
    if (state.activeProviderId == providerId) return;
    _searchService.setActiveProvider(providerId);
    state = state.copyWith(activeProviderId: providerId);
    if (state.currentQuery.isNotEmpty) {
      search(state.currentQuery);
    } else {
      loadTrending();
    }
  }
}
