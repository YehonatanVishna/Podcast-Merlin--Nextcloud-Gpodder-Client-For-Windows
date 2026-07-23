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
      'rss_url': rssUrl,
      'title': title,
      'image_url': imageUrl,
      'description': description,
      'link': link,
      'last_updated': lastUpdated?.toIso8601String(),
    };
  }

  factory Podcast.fromMap(Map<String, dynamic> map) {
    return Podcast(
      id: map['id'] as int?,
      rssUrl: (map['rss_url'] ?? '').toString(),
      title: (map['title'] ?? 'Untitled Podcast').toString(),
      imageUrl: (map['image_url'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      link: (map['link'] ?? '').toString(),
      lastUpdated: map['last_updated'] != null
          ? DateTime.tryParse(map['last_updated'].toString())
          : null,
    );
  }
}
