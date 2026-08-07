enum SyncStage {
  idle,
  connectingGpodder,
  pushingActions,
  fetchingSubscriptions,
  fetchingEpisodeActions,
  fetchingFeed,
  completed,
  error,
}

class SyncStatusState {
  final bool isSyncing;
  final SyncStage stage;
  final String? currentTask;
  final String? activeFeedUrl;
  final String? error;
  final List<String> feedWarnings;

  const SyncStatusState({
    this.isSyncing = false,
    this.stage = SyncStage.idle,
    this.currentTask,
    this.activeFeedUrl,
    this.error,
    this.feedWarnings = const [],
  });

  bool get hasFeedWarnings => feedWarnings.isNotEmpty;

  SyncStatusState copyWith({
    bool? isSyncing,
    SyncStage? stage,
    String? currentTask,
    String? activeFeedUrl,
    String? error,
    List<String>? feedWarnings,
  }) {
    return SyncStatusState(
      isSyncing: isSyncing ?? this.isSyncing,
      stage: stage ?? this.stage,
      currentTask: currentTask,
      activeFeedUrl: activeFeedUrl,
      error: error,
      feedWarnings: feedWarnings ?? this.feedWarnings,
    );
  }
}
