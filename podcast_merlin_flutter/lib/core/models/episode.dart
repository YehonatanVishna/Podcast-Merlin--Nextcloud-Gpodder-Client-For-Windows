enum EpisodeFilter { all, unplayed, finished }

class Episode {
  final int? id;
  final int? podcastId;
  final String guid;
  final String title;
  final String mediaUrl;
  final String description;
  final DateTime? publishedAt;
  final int duration; // in seconds
  final int position; // in seconds
  final bool isPlayed;
  final String imageUrl;
  final String podcastRss;

  const Episode({
    this.id,
    this.podcastId,
    required this.guid,
    required this.title,
    required this.mediaUrl,
    required this.description,
    this.publishedAt,
    this.duration = 0,
    this.position = 0,
    this.isPlayed = false,
    required this.imageUrl,
    required this.podcastRss,
  });

  double get progressPercentage {
    if (duration <= 0) return 0.0;
    final pct = position / duration;
    return pct > 1.0 ? 1.0 : (pct < 0.0 ? 0.0 : pct);
  }

  bool get isFinished {
    if (isPlayed) return true;
    if (duration > 0 && position >= (duration - 10)) return true;
    return false;
  }

  Episode copyWith({
    int? id,
    int? podcastId,
    String? guid,
    String? title,
    String? mediaUrl,
    String? description,
    DateTime? publishedAt,
    int? duration,
    int? position,
    bool? isPlayed,
    String? imageUrl,
    String? podcastRss,
  }) {
    return Episode(
      id: id ?? this.id,
      podcastId: podcastId ?? this.podcastId,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      description: description ?? this.description,
      publishedAt: publishedAt ?? this.publishedAt,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      isPlayed: isPlayed ?? this.isPlayed,
      imageUrl: imageUrl ?? this.imageUrl,
      podcastRss: podcastRss ?? this.podcastRss,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (podcastId != null) 'podcastId': podcastId,
      'guid': guid,
      'title': title,
      'mediaUrl': mediaUrl,
      'description': description,
      'pubDate': publishedAt?.toIso8601String(),
      'duration': duration,
      'position': position,
      'isPlayed': isPlayed ? 1 : 0,
      'imageUrl': imageUrl,
    };
  }

  factory Episode.fromMap(Map<String, dynamic> map) {
    final pubDateVal = map['pubDate'] ?? map['published_at'];
    return Episode(
      id: map['id'] as int?,
      podcastId: (map['podcastId'] ?? map['podcast_id']) as int?,
      guid: (map['guid'] ?? '').toString(),
      title: (map['title'] ?? 'Untitled Episode').toString(),
      mediaUrl: (map['mediaUrl'] ?? map['media_url'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      publishedAt: pubDateVal != null ? DateTime.tryParse(pubDateVal.toString()) : null,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      position: (map['position'] as num?)?.toInt() ?? 0,
      isPlayed: (map['isPlayed'] ?? map['is_played'] as int? ?? 0) == 1,
      imageUrl: (map['imageUrl'] ?? map['image_url'] ?? '').toString(),
      podcastRss: (map['podcastRss'] ?? map['podcast_rss'] ?? '').toString(),
    );
  }
}

