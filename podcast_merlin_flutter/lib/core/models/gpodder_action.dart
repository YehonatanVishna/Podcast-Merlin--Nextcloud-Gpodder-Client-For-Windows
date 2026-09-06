class GPodderAction {
  final int? id;
  final String podcast;
  final String episode;
  final String? guid;
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
    this.guid,
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
    String? guid,
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
      guid: guid ?? this.guid,
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
      if (guid != null && guid!.isNotEmpty) 'guid': guid,
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
      if (guid != null) 'guid': guid,
      'action': action,
      'timestamp': timestamp.toIso8601String(),
      'position': position,
      'started': started,
      'total': total,
      'device': device,
      'status': status,
    };
  }

  static int _parseSafeInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    if (val is String) {
      final s = val.trim();
      if (s.isEmpty) return fallback;
      final asInt = int.tryParse(s);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(s);
      if (asDouble != null) return asDouble.toInt();
    }
    return fallback;
  }

  factory GPodderAction.fromMap(Map<String, dynamic> map) {
    DateTime parsedTime;
    final tsRaw = map['timestamp'];
    if (tsRaw is num) {
      final sec = tsRaw.toInt();
      // Handle both seconds (standard UNIX epoch) and milliseconds
      parsedTime = DateTime.fromMillisecondsSinceEpoch(
        sec > 100000000000 ? sec : sec * 1000,
      );
    } else if (tsRaw is String) {
      final s = tsRaw.trim();
      final parsedNum = num.tryParse(s);
      if (parsedNum != null) {
        final sec = parsedNum.toInt();
        parsedTime = DateTime.fromMillisecondsSinceEpoch(
          sec > 100000000000 ? sec : sec * 1000,
        );
      } else {
        parsedTime = DateTime.tryParse(s) ?? DateTime.now();
      }
    } else {
      parsedTime = DateTime.now();
    }

    final podcastVal = map['podcast'] ??
        map['podcastUrl'] ??
        map['podcast_url'] ??
        map['feed'] ??
        map['feed_url'] ??
        map['feedUrl'] ??
        '';
    final episodeVal = map['episode'] ??
        map['episodeUrl'] ??
        map['episode_url'] ??
        map['media_url'] ??
        map['mediaUrl'] ??
        map['url'] ??
        '';
    final guidVal = map['guid'] ??
        map['guid_url'] ??
        map['guidUrl'] ??
        map['item_identifier'] ??
        map['itemIdentifier'];
    final totalVal = map['total'] ??
        map['totalDuration'] ??
        map['total_duration'] ??
        0;

    final idVal = map['id'];
    final actionVal = map['action']?.toString().toLowerCase().trim() ?? 'play';

    return GPodderAction(
      id: idVal == null ? null : _parseSafeInt(idVal),
      podcast: podcastVal.toString(),
      episode: episodeVal.toString(),
      guid: guidVal?.toString(),
      action: actionVal,
      timestamp: parsedTime,
      position: _parseSafeInt(map['position']),
      started: _parseSafeInt(map['started']),
      total: _parseSafeInt(totalVal),
      device: map['device']?.toString() ?? 'podcast_merlin_flutter',
      status: map['status']?.toString() ?? 'pending',
    );
  }
}
