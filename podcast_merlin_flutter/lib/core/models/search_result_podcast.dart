class SearchResultPodcast {
  final String title;
  final String author;
  final String rssUrl;
  final String imageUrl;
  final String description;
  final String websiteUrl;
  final List<String> categories;
  final int? episodeCount;
  final String? language;
  final String providerId;

  const SearchResultPodcast({
    required this.title,
    required this.author,
    required this.rssUrl,
    required this.imageUrl,
    required this.description,
    required this.websiteUrl,
    this.categories = const [],
    this.episodeCount,
    this.language,
    required this.providerId,
  });

  factory SearchResultPodcast.fromPodcastIndexJson(Map<String, dynamic> json) {
    final categoriesMap = json['categories'];
    List<String> parsedCategories = [];
    if (categoriesMap is Map) {
      parsedCategories = categoriesMap.values.map((v) => v.toString()).toList();
    } else if (categoriesMap is List) {
      parsedCategories = categoriesMap.map((v) => v.toString()).toList();
    }

    return SearchResultPodcast(
      title: (json['title'] ?? 'Untitled Podcast').toString(),
      author: (json['author'] ?? json['ownerName'] ?? '').toString(),
      rssUrl: (json['url'] ?? json['originalUrl'] ?? '').toString(),
      imageUrl: (json['image'] ?? json['artwork'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      websiteUrl: (json['link'] ?? '').toString(),
      categories: parsedCategories,
      episodeCount: json['episodeCount'] as int?,
      language: json['language']?.toString(),
      providerId: 'podcast_index',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      'rssUrl': rssUrl,
      'imageUrl': imageUrl,
      'description': description,
      'websiteUrl': websiteUrl,
      'categories': categories,
      'episodeCount': episodeCount,
      'language': language,
      'providerId': providerId,
    };
  }
}
