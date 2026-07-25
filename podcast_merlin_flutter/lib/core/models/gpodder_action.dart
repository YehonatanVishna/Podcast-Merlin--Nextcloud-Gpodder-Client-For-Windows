class GPodderAction {
  final int? id;
  final String podcast;
  final String episode;
  final String action; // 'play', 'new', 'delete'
  final DateTime timestamp;
  final int position;
  final int started;
  final int total;
  final String device;
  final String status; // 'pending', 'synced'

  const GPodderAction({
    this.id,
    required this.podcast,
    required this.episode,
    required this.action,
    required this.timestamp,
    this.position = 0,
    this.started = 0,
    this.total = 0,
    this.device = 'podcast_merlin_flutter',
    this.status = 'pending',
  });

  String get podcastUrl => podcast;
  String get episodeUrl => episode;
  String get podcastFeedUrl => podcast;
  String get episodeMediaUrl => episode;

  GPodderAction copyWith({
    int? id,
    String? podcast,
    String? episode,
    String? action,
    DateTime? timestamp,
    int? position,
    int? started,
    int? total,
    String? device,
    String? status,
  }) {
    return GPodderAction(
      id: id ?? this.id,
      podcast: podcast ?? this.podcast,
      episode: episode ?? this.episode,
      action: action ?? this.action,
      timestamp: timestamp ?? this.timestamp,
      position: position ?? this.position,
      started: started ?? this.started,
      total: total ?? this.total,
      device: device ?? this.device,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'podcast': podcast,
      'episode': episode,
      'action': action,
      'timestamp': timestamp.toUtc().toIso8601String().split('.').first,
      if (action == 'play') 'position': position,
      if (action == 'play') 'started': started,
      if (action == 'play') 'total': total,
      'device': device,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'podcast': podcast,
      'episode': episode,
      'action': action,
      'timestamp': timestamp.toIso8601String(),
      'position': position,
      'started': started,
      'total': total,
      'device': device,
      'status': status,
    };
  }

  factory GPodderAction.fromMap(Map<String, dynamic> map) {
    DateTime parsedTime;
    final tsRaw = map['timestamp'];
    if (tsRaw is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000);
    } else if (tsRaw is String) {
      final parsedInt = int.tryParse(tsRaw);
      if (parsedInt != null) {
        parsedTime = DateTime.fromMillisecondsSinceEpoch(parsedInt * 1000);
      } else {
        parsedTime = DateTime.tryParse(tsRaw) ?? DateTime.now();
      }
    } else {
      parsedTime = DateTime.now();
    }

    final podcastVal = map['podcast'] ?? map['podcastUrl'] ?? map['podcast_url'] ?? '';
    final episodeVal = map['episode'] ?? map['episodeUrl'] ?? map['episode_url'] ?? '';
    final totalVal = map['total'] ?? map['totalDuration'] ?? map['total_duration'] ?? 0;

    return GPodderAction(
      id: map['id'] as int?,
      podcast: podcastVal.toString(),
      episode: episodeVal.toString(),
      action: map['action'] as String? ?? 'play',
      timestamp: parsedTime,
      position: (map['position'] as num?)?.toInt() ?? 0,
      started: (map['started'] as num?)?.toInt() ?? 0,
      total: (totalVal as num?)?.toInt() ?? 0,
      device: map['device'] as String? ?? 'podcast_merlin_flutter',
      status: map['status'] as String? ?? 'pending',
    );
  }
}
