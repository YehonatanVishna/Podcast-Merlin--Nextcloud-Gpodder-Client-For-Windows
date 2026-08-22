import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../../core/models/episode.dart';
import '../../core/utils/error_formatter.dart';
import '../../core/utils/html_purifier.dart';

class _XmlParseArgs {
  final String xmlString;
  final String rssUrl;

  _XmlParseArgs(this.xmlString, this.rssUrl);
}

RssFeedResult _parseXmlInBackground(_XmlParseArgs args) {
  final parser = RssFeedParser();
  return parser.parseFeedXml(args.xmlString, args.rssUrl);
}

class RssParseException implements Exception {
  final String message;
  RssParseException(this.message);

  @override
  String toString() => message;
}

class RssFeedResult {
  final String title;
  final String imageUrl;
  final String description;
  final String link;
  final List<Episode> episodes;

  RssFeedResult({
    required this.title,
    required this.imageUrl,
    required this.description,
    required this.link,
    required this.episodes,
  });
}

class RssFeedParser {
  final Dio _dio;

  RssFeedParser({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent': 'PodcastMerlin/2.0 (Flutter RSS Reader)',
                },
              ),
            );

  Future<RssFeedResult?> parseFeedFromUrl(String rssUrl) async {
    final trimmedUrl = rssUrl.trim();
    if (trimmedUrl.isEmpty) {
      throw RssParseException('Invalid feed URL: URL cannot be empty.');
    }
    final parsedUri = Uri.tryParse(trimmedUrl);
    if (parsedUri == null || (!parsedUri.isScheme('http') && !parsedUri.isScheme('https'))) {
      throw RssParseException('Invalid feed URL scheme. Must begin with http:// or https://');
    }

    try {
      final response = await _dio.get<String>(trimmedUrl);
      if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
        return await compute(_parseXmlInBackground, _XmlParseArgs(response.data!, trimmedUrl));
      } else {
        throw RssParseException('Failed to fetch feed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (e is RssParseException) rethrow;
      throw RssParseException('Feed download error: ${AppErrorFormatter.format(e)}');
    }
  }

  Future<RssFeedResult> parseFeedXmlAsync(String xmlString, String rssUrl) async {
    return await compute(_parseXmlInBackground, _XmlParseArgs(xmlString, rssUrl));
  }

  RssFeedResult parseFeedXml(String xmlString, String rssUrl) {
    if (xmlString.trim().isEmpty) {
      throw RssParseException('RSS feed XML content is empty.');
    }

    XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } catch (e) {
      throw RssParseException('Malformed XML: ${AppErrorFormatter.format(e)}');
    }

    final channel = document.findAllElements('channel').firstOrNull ??
        (document.rootElement.name.local == 'feed' ? document.rootElement : null);

    if (channel == null) {
      throw RssParseException('Invalid RSS/Atom feed format: missing channel or feed root.');
    }

    final title = _getElementText(channel, 'title') ?? 'Untitled Podcast';
    final rawDesc = _getElementText(channel, 'description') ?? _getElementText(channel, 'summary') ?? '';
    final description = _sanitizeText(rawDesc);
    final link = _getElementText(channel, 'link') ?? rssUrl;

    String imageUrl = _getItunesImage(channel) ?? '';
    if (imageUrl.isEmpty) {
      final imageElement = channel.findElements('image').firstOrNull;
      if (imageElement != null) {
        imageUrl = _getElementText(imageElement, 'url') ?? '';
      }
    }

    final episodes = <Episode>[];
    // Support both RSS <item> and Atom <entry>
    var items = channel.findElements('item');
    if (items.isEmpty) {
      items = channel.findElements('entry');
    }

    for (final item in items) {
      final epTitle = _getElementText(item, 'title') ?? 'Untitled Episode';
      final epGuid = _getElementText(item, 'guid') ?? _getElementText(item, 'id') ?? _getEnclosureUrl(item) ?? epTitle;
      final epMediaUrl = _getEnclosureUrl(item);

      if (epMediaUrl == null || epMediaUrl.isEmpty) continue;

      final rawEpDesc = _getElementText(item, 'description') ??
          _getElementText(item, 'content:encoded') ??
          _getElementText(item, 'content') ??
          _getElementText(item, 'itunes:summary') ??
          '';
      final epDescription = _sanitizeText(rawEpDesc);

      final pubDateStr = _getElementText(item, 'pubDate') ?? _getElementText(item, 'published') ?? _getElementText(item, 'updated');
      final publishedAt = _parseDate(pubDateStr);

      final durationStr = _getElementText(item, 'itunes:duration') ?? '0';
      final durationSeconds = _parseDuration(durationStr);

      final epImageUrl = _getItunesImage(item) ?? imageUrl;

      episodes.add(
        Episode(
          guid: epGuid,
          title: epTitle,
          mediaUrl: epMediaUrl,
          description: epDescription,
          publishedAt: publishedAt,
          duration: durationSeconds,
          position: 0,
          isPlayed: false,
          imageUrl: epImageUrl,
          podcastRss: rssUrl,
        ),
      );
    }

    return RssFeedResult(
      title: title,
      imageUrl: imageUrl,
      description: description,
      link: link,
      episodes: episodes,
    );
  }

  String? _getElementText(XmlElement element, String tagName) {
    for (final child in element.children) {
      if (child is XmlElement && (child.name.qualified == tagName || child.name.local == tagName)) {
        return child.innerText.trim();
      }
    }
    return null;
  }

  String? _getItunesImage(XmlElement element) {
    for (final child in element.children) {
      if (child is XmlElement && (child.name.qualified == 'itunes:image' || child.name.local == 'image')) {
        final href = child.getAttribute('href');
        if (href != null && href.isNotEmpty) return href;
      }
    }
    return null;
  }

  String? _getEnclosureUrl(XmlElement element) {
    for (final child in element.children) {
      if (child is XmlElement && (child.name.qualified == 'enclosure' || child.name.local == 'link')) {
        final url = child.getAttribute('url') ?? child.getAttribute('href');
        final rel = child.getAttribute('rel');
        if (url != null && url.isNotEmpty) {
          if (rel == null || rel == 'enclosure' || url.endsWith('.mp3') || url.endsWith('.m4a')) {
            return url;
          }
        }
      }
    }
    return null;
  }

  String _sanitizeText(String rawText) {
    return HtmlPurifier.purify(rawText);
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}

    try {
      var cleaned = dateStr.trim();
      if (cleaned.contains(',')) {
        cleaned = cleaned.split(',').last.trim();
      }
      final parts = cleaned.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final day = int.tryParse(parts[0]);
        final monthRaw = parts[1].toLowerCase();
        final year = int.tryParse(parts[2]);

        if (monthRaw.length >= 3) {
          const monthMap = {
            'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
            'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
          };
          final month = monthMap[monthRaw.substring(0, 3)];

          if (day != null && month != null && year != null) {
            int hour = 0, minute = 0, second = 0;
            if (parts.length >= 4 && parts[3].contains(':')) {
              final timeParts = parts[3].split(':');
              hour = int.tryParse(timeParts[0]) ?? 0;
              minute = int.tryParse(timeParts[1]) ?? 0;
              if (timeParts.length > 2) {
                second = (double.tryParse(timeParts[2]) ?? 0).toInt();
              }
            }
            return DateTime.utc(year, month, day, hour, minute, second);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  int _parseDuration(String durationStr) {
    final cleaned = durationStr.trim();
    if (cleaned.isEmpty) return 0;

    // Case 1: Pure integer/float seconds
    final secondsDouble = double.tryParse(cleaned);
    if (secondsDouble != null) return secondsDouble.toInt();

    // Case 2: HH:MM:SS or MM:SS
    if (cleaned.contains(':')) {
      final parts = cleaned.split(':');
      try {
        if (parts.length == 3) {
          final h = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          final s = (double.tryParse(parts[2]) ?? 0).toInt();
          return (h * 3600) + (m * 60) + s;
        } else if (parts.length == 2) {
          final m = int.parse(parts[0]);
          final s = (double.tryParse(parts[1]) ?? 0).toInt();
          return (m * 60) + s;
        }
      } catch (_) {}
    }
    return 0;
  }
}
