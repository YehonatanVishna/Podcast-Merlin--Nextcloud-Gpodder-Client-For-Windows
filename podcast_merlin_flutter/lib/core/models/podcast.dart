class Podcast {
  final int? id;
  final String rssUrl;
  final String title;
  final String imageUrl;
  final String description;
  final String link;
  final DateTime? lastUpdated;

  const Podcast({
    this.id,
    required this.rssUrl,
    required this.title,
    required this.imageUrl,
    required this.description,
    required this.link,
    this.lastUpdated,
  });

  Podcast copyWith({
    int? id,
    String? rssUrl,
    String? title,
    String? imageUrl,
    String? description,
    String? link,
    DateTime? lastUpdated,
  }) {
    return Podcast(
      id: id ?? this.id,
      rssUrl: rssUrl ?? this.rssUrl,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      link: link ?? this.link,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'rssUrl': rssUrl,
      'title': title,
      'imageUrl': imageUrl,
      'description': description,
      'websiteUrl': link,
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  factory Podcast.fromMap(Map<String, dynamic> map) {
    final lastUpdatedVal = map['lastUpdated'] ?? map['last_updated'];
    return Podcast(
      id: map['id'] as int?,
      rssUrl: (map['rssUrl'] ?? map['rss_url'] ?? '').toString(),
      title: (map['title'] ?? 'Untitled Podcast').toString(),
      imageUrl: (map['imageUrl'] ?? map['image_url'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      link: (map['websiteUrl'] ?? map['link'] ?? '').toString(),
      lastUpdated: lastUpdatedVal != null ? DateTime.tryParse(lastUpdatedVal.toString()) : null,
    );
  }
}
