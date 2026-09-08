import 'package:xml/xml.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/podcast.dart';

class OpmlOutline {
  final String title;
  final String xmlUrl;
  final String htmlUrl;
  final String text;
  final String description;

  const OpmlOutline({
    required this.title,
    required this.xmlUrl,
    this.htmlUrl = '',
    this.text = '',
    this.description = '',
  });

  @override
  String toString() =>
      'OpmlOutline(title: $title, xmlUrl: $xmlUrl, htmlUrl: $htmlUrl, text: $text, description: $description)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpmlOutline &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          xmlUrl == other.xmlUrl &&
          htmlUrl == other.htmlUrl &&
          text == other.text &&
          description == other.description;

  @override
  int get hashCode => Object.hash(title, xmlUrl, htmlUrl, text, description);
}

class OpmlService {
  /// Parses OPML XML content into a flat list of podcast outlines.
  /// Recursively traverses nested outlines (e.g. folders / categories).
  /// Gracefully catches XML parse errors and returns empty list or partial list without throwing.
  static List<OpmlOutline> parseOpml(String xmlContent) {
    final trimmed = xmlContent.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final document = XmlDocument.parse(trimmed);
      final outlines = <OpmlOutline>[];

      void extractOutlines(XmlElement parent) {
        for (final child in parent.children.whereType<XmlElement>()) {
          if (child.name.local.toLowerCase() == 'outline') {
            final xmlUrl = _getAttribute(child, ['xmlUrl', 'xmlurl', 'url']);
            final htmlUrl = _getAttribute(child, ['htmlUrl', 'htmlurl']);
            final text = _getAttribute(child, ['text']);
            final title = _getAttribute(child, ['title']);
            final description = _getAttribute(child, ['description']);

            final effectiveTitle = title.isNotEmpty ? title : (text.isNotEmpty ? text : '');
            final effectiveText = text.isNotEmpty ? text : (title.isNotEmpty ? title : '');

            if (xmlUrl.isNotEmpty) {
              outlines.add(OpmlOutline(
                title: effectiveTitle,
                xmlUrl: xmlUrl,
                htmlUrl: htmlUrl,
                text: effectiveText,
                description: description,
              ));
            }

            // Recursively search child outlines (e.g. for folders/categories)
            extractOutlines(child);
          } else {
            extractOutlines(child);
          }
        }
      }

      final bodyElements = document.findAllElements('body');
      if (bodyElements.isNotEmpty) {
        for (final body in bodyElements) {
          extractOutlines(body);
        }
      } else {
        // Fallback: search all outline elements directly if no <body> exists
        for (final outline in document.findAllElements('outline')) {
          final xmlUrl = _getAttribute(outline, ['xmlUrl', 'xmlurl', 'url']);
          final htmlUrl = _getAttribute(outline, ['htmlUrl', 'htmlurl']);
          final text = _getAttribute(outline, ['text']);
          final title = _getAttribute(outline, ['title']);
          final description = _getAttribute(outline, ['description']);

          final effectiveTitle = title.isNotEmpty ? title : (text.isNotEmpty ? text : '');
          final effectiveText = text.isNotEmpty ? text : (title.isNotEmpty ? title : '');

          if (xmlUrl.isNotEmpty && !outlines.any((o) => o.xmlUrl == xmlUrl)) {
            outlines.add(OpmlOutline(
              title: effectiveTitle,
              xmlUrl: xmlUrl,
              htmlUrl: htmlUrl,
              text: effectiveText,
              description: description,
            ));
          }
        }
      }

      return outlines;
    } catch (_) {
      return const [];
    }
  }

  static String _getAttribute(XmlElement element, List<String> names) {
    for (final name in names) {
      for (final attr in element.attributes) {
        if (attr.name.local.toLowerCase() == name.toLowerCase()) {
          final val = attr.value.trim();
          if (val.isNotEmpty) return val;
        }
      }
    }
    return '';
  }

  /// Builds a valid OPML 2.0 XML string from a list of podcasts using `package:xml`.
  static String generateOpml({
    required List<Podcast> podcasts,
    String title = 'Podcast Merlin Subscriptions',
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('opml', attributes: {'version': '2.0'}, nest: () {
      builder.element('head', nest: () {
        builder.element('title', nest: () => builder.text(title));
        builder.element('dateCreated', nest: () => builder.text(DateTime.now().toUtc().toIso8601String()));
        builder.element('docs', nest: () => builder.text('http://opml.org/spec2.opml'));
      });
      builder.element('body', nest: () {
        for (final podcast in podcasts) {
          final effectiveTitle = podcast.title.isNotEmpty ? podcast.title : 'Untitled Podcast';
          final attributes = <String, String>{
            'type': 'rss',
            'text': effectiveTitle,
            'title': effectiveTitle,
            'xmlUrl': podcast.rssUrl,
            'htmlUrl': podcast.link.isNotEmpty ? podcast.link : (podcast.websiteUrl),
          };
          if (podcast.description.isNotEmpty) {
            attributes['description'] = podcast.description;
          }
          builder.element('outline', attributes: attributes);
        }
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  /// Parses OPML, checks for existing podcast subscriptions, inserts new ones,
  /// and enqueues gPodder subscription actions if syncWithServer is true.
  static Future<List<Podcast>> importOpml(
    String xmlContent,
    DatabaseHelper db, {
    bool syncWithServer = true,
  }) async {
    final outlines = parseOpml(xmlContent);
    final imported = <Podcast>[];

    for (final outline in outlines) {
      if (outline.xmlUrl.trim().isEmpty) continue;
      final existing = await db.getPodcastByUrl(outline.xmlUrl);
      if (existing == null) {
        final title = outline.title.isNotEmpty
            ? outline.title
            : (outline.text.isNotEmpty ? outline.text : 'Untitled Podcast');
        final podcast = Podcast(
          rssUrl: outline.xmlUrl,
          title: title,
          link: outline.htmlUrl,
          description: outline.description,
          imageUrl: '',
          lastUpdated: DateTime.now(),
        );
        final id = await db.insertPodcast(podcast);
        imported.add(podcast.copyWith(id: id));

        if (syncWithServer) {
          await db.queueSubscriptionChange('add', outline.xmlUrl);
        }
      }
    }

    return imported;
  }
}

// Top-level convenience wrappers matching prompt signatures
List<OpmlOutline> parseOpml(String xmlContent) => OpmlService.parseOpml(xmlContent);

String generateOpml({
  required List<Podcast> podcasts,
  String title = 'Podcast Merlin Subscriptions',
}) =>
    OpmlService.generateOpml(podcasts: podcasts, title: title);

Future<List<Podcast>> importOpml(
  String xmlContent,
  DatabaseHelper db, {
  bool syncWithServer = true,
}) =>
    OpmlService.importOpml(xmlContent, db, syncWithServer: syncWithServer);
