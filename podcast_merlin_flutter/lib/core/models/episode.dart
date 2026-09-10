enum EpisodeFilter { all, unplayed, inProgress, starred, finished, downloaded }

enum DownloadStatus { none, queued, downloading, downloaded, failed }

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
  final bool isStarred;
  final String imageUrl;
  final String podcastRss;
  final String? downloadPath;
  final DownloadStatus downloadStatus;
  final double downloadProgress; // 0.0 to 1.0
  final int downloadedBytes;
  final int totalBytes;

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
    this.isStarred = false,
    required this.imageUrl,
    required this.podcastRss,
    this.downloadPath,
    this.downloadStatus = DownloadStatus.none,
    this.downloadProgress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
  });

  bool get isDownloaded => downloadStatus == DownloadStatus.downloaded && downloadPath != null;
  bool get isDownloading => downloadStatus == DownloadStatus.downloading || downloadStatus == DownloadStatus.queued;

  double get progressPercentage {
    if (duration <= 0) return 0.0;
    final pct = position / duration;
    return pct > 1.0 ? 1.0 : (pct < 0.0 ? 0.0 : pct);
  }

  bool get isFinished {
    if (isPlayed) return true;
    if (position > 0 && duration > 0) {
      if (duration > 60) {
        return (duration - position) <= 60;
      } else {
        return position >= (duration > 10 ? duration - 10 : duration);
      }
    }
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
    bool? isStarred,
    String? imageUrl,
    String? podcastRss,
    String? downloadPath,
    DownloadStatus? downloadStatus,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
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
      isStarred: isStarred ?? this.isStarred,
      imageUrl: imageUrl ?? this.imageUrl,
      podcastRss: podcastRss ?? this.podcastRss,
      downloadPath: downloadPath ?? this.downloadPath,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
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
      'isStarred': isStarred ? 1 : 0,
      'imageUrl': imageUrl,
      'downloadPath': downloadPath,
      'downloadStatus': downloadStatus.name,
      'downloadProgress': downloadProgress,
      'downloadedBytes': downloadedBytes,
      'totalBytes': totalBytes,
    };
  }

  static int? _parseOptionalInt(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is String) {
      final s = val.trim();
      if (s.isEmpty) return null;
      final asInt = int.tryParse(s);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(s);
      if (asDouble != null) return asDouble.toInt();
    }
    return null;
  }

  static int _parseInt(dynamic val, [int fallback = 0]) =>
      _parseOptionalInt(val) ?? fallback;

  static double _parseDouble(dynamic val, [double fallback = 0.0]) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) {
      final s = val.trim();
      if (s.isEmpty) return fallback;
      final asDouble = double.tryParse(s);
      if (asDouble != null) return asDouble;
    }
    return fallback;
  }

  static bool _parseBool(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final s = val.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }
    return false;
  }

  static DownloadStatus _parseDownloadStatus(dynamic val) {
    if (val == null) return DownloadStatus.none;
    final str = val.toString().trim().toLowerCase();
    for (final s in DownloadStatus.values) {
      if (s.name.toLowerCase() == str) return s;
    }
    return DownloadStatus.none;
  }

  factory Episode.fromMap(Map<String, dynamic> map) {
    final pubDateVal = map['pubDate'] ?? map['published_at'];
    final isPlayedVal = map['isPlayed'] ?? map['is_played'];
    final isStarredVal = map['isStarred'] ?? map['is_starred'];
    return Episode(
      id: _parseOptionalInt(map['id']),
      podcastId: _parseOptionalInt(map['podcastId'] ?? map['podcast_id']),
      guid: (map['guid'] ?? '').toString(),
      title: (map['title'] ?? 'Untitled Episode').toString(),
      mediaUrl: (map['mediaUrl'] ?? map['media_url'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      publishedAt: pubDateVal != null ? DateTime.tryParse(pubDateVal.toString()) : null,
      duration: _parseInt(map['duration']),
      position: _parseInt(map['position']),
      isPlayed: _parseBool(isPlayedVal),
      isStarred: _parseBool(isStarredVal),
      imageUrl: (map['imageUrl'] ?? map['image_url'] ?? '').toString(),
      podcastRss: (map['podcastRss'] ?? map['podcast_rss'] ?? '').toString(),
      downloadPath: (map['downloadPath'] ?? map['download_path']) as String?,
      downloadStatus: _parseDownloadStatus(map['downloadStatus'] ?? map['download_status']),
      downloadProgress: _parseDouble(map['downloadProgress'] ?? map['download_progress']),
      downloadedBytes: _parseInt(map['downloadedBytes'] ?? map['downloaded_bytes']),
      totalBytes: _parseInt(map['totalBytes'] ?? map['total_bytes']),
    );
  }
}

