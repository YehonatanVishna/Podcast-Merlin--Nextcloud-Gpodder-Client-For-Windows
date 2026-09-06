import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/features/podcasts/rss_feed_parser.dart';

void main() {
  group('RssFeedParser Tests', () {
    late RssFeedParser parser;

    setUp(() {
      parser = RssFeedParser();
    });

    test('parseFeedXml parses valid RSS 2.0 feed correctly', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Tech Merlin Podcast</title>
    <description>All about software and tech.</description>
    <link>https://example.com/podcast</link>
    <itunes:image href="https://example.com/cover.png"/>
    <item>
      <title>Episode 1: Launching Merlin</title>
      <guid>ep-1</guid>
      <description><![CDATA[<p>Welcome to <b>Merlin</b> <script>alert(1)</script></p>]]></description>
      <pubDate>Mon, 01 Jan 2026 10:00:00 GMT</pubDate>
      <itunes:duration>01:15:30</itunes:duration>
      <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg" length="12345"/>
    </item>
  </channel>
</rss>''';

      final result = parser.parseFeedXml(xml, 'https://example.com/feed.xml');

      expect(result.title, 'Tech Merlin Podcast');
      expect(result.description, 'All about software and tech.');
      expect(result.link, 'https://example.com/podcast');
      expect(result.imageUrl, 'https://example.com/cover.png');
      expect(result.episodes.length, 1);

      final ep = result.episodes.first;
      expect(ep.title, 'Episode 1: Launching Merlin');
      expect(ep.guid, 'ep-1');
      expect(ep.mediaUrl, 'https://example.com/ep1.mp3');
      expect(ep.duration, 4530); // 1h 15m 30s = 4530 seconds
      expect(ep.publishedAt, equals(DateTime.utc(2026, 1, 1, 10, 0, 0)));
      expect(ep.description.contains('<script>'), false);
      expect(ep.description.contains('<b>Merlin</b>'), true);
    });

    test('parseFeedXml handles duration formats: seconds, MM:SS, HH:MM:SS', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Duration Test</title>
    <item>
      <title>Ep 1</title>
      <enclosure url="https://example.com/1.mp3"/>
      <itunes:duration>300</itunes:duration>
    </item>
    <item>
      <title>Ep 2</title>
      <enclosure url="https://example.com/2.mp3"/>
      <itunes:duration>10:30</itunes:duration>
    </item>
    <item>
      <title>Ep 3</title>
      <enclosure url="https://example.com/3.mp3"/>
      <itunes:duration>02:00:15</itunes:duration>
    </item>
  </channel>
</rss>''';

      final result = parser.parseFeedXml(xml, 'https://example.com/durations.xml');
      expect(result.episodes.length, 3);
      expect(result.episodes[0].duration, 300);
      expect(result.episodes[1].duration, 630); // 10m 30s
      expect(result.episodes[2].duration, 7215); // 2h 0m 15s
    });

    test('parseFeedXml ignores items without audio enclosure', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Blog Feed</title>
    <item>
      <title>Text post without audio</title>
      <description>No audio here</description>
    </item>
    <item>
      <title>Podcast Post</title>
      <enclosure url="https://example.com/audio.mp3"/>
    </item>
  </channel>
</rss>''';

      final result = parser.parseFeedXml(xml, 'https://example.com/blog.xml');
      expect(result.episodes.length, 1);
      expect(result.episodes.first.title, 'Podcast Post');
    });

    test('parseFeedXml supports Atom feed entries with link rel enclosure', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Feed Podcast</title>
  <link href="https://example.com"/>
  <entry>
    <title>Atom Ep 1</title>
    <id>atom-guid-1</id>
    <link rel="enclosure" href="https://example.com/atom1.mp3"/>
    <updated>2026-07-20T15:30:00Z</updated>
  </entry>
</feed>''';

      final result = parser.parseFeedXml(xml, 'https://example.com/atom.xml');
      expect(result.title, 'Atom Feed Podcast');
      expect(result.episodes.length, 1);
      expect(result.episodes.first.guid, 'atom-guid-1');
      expect(result.episodes.first.mediaUrl, 'https://example.com/atom1.mp3');
      expect(result.episodes.first.publishedAt, DateTime.utc(2026, 7, 20, 15, 30, 0));
    });
  });
}
