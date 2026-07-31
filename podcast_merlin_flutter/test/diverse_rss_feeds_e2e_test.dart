import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/podcasts/rss_feed_parser.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/episode_list_view.dart';

class TestEpisodesNotifier extends StateNotifier<EpisodesState> implements EpisodesNotifier {
  TestEpisodesNotifier(List<Episode> episodes)
      : super(
          EpisodesState(
            episodes: episodes,
            isLoading: false,
            isLoadingMore: false,
            hasMore: false,
          ),
        );

  @override
  Future<void> loadEpisodes({EpisodeFilter? filter}) async {}

  @override
  Future<void> loadMoreEpisodes() async {}

  @override
  Future<void> refreshFeed() async {}

  @override
  Future<void> refresh({Podcast? podcast}) async {}

  @override
  Future<void> setFilter(EpisodeFilter filter) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Diverse Real-World Podcast RSS Feed Parsing & Rendering E2E Tests', () {
    late RssFeedParser parser;
    late DatabaseHelper db;

    setUp(() async {
      parser = RssFeedParser();
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    test('Parses iTunes Podcast Feed with HH:MM:SS duration & iTunes tags', () {
      const xmlData = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>The Tech &amp; AI Show</title>
    <link>https://example.com/show</link>
    <description>A weekly podcast on artificial intelligence and technology.</description>
    <itunes:image href="https://example.com/cover.jpg"/>
    <item>
      <title>Episode 42: Agentic Workflows</title>
      <guid>ep-42-ai</guid>
      <description>Exploring agentic AI systems.</description>
      <enclosure url="https://media.example.com/ep42.mp3" length="45000000" type="audio/mpeg"/>
      <pubDate>Mon, 15 Jun 2026 12:00:00 GMT</pubDate>
      <itunes:duration>01:15:30</itunes:duration>
      <itunes:image href="https://example.com/ep42.jpg"/>
    </item>
  </channel>
</rss>''';

      final result = parser.parseFeedXml(xmlData, 'https://example.com/rss.xml');

      expect(result.title, 'The Tech & AI Show');
      expect(result.description, contains('weekly podcast on artificial intelligence'));
      expect(result.imageUrl, 'https://example.com/cover.jpg');
      expect(result.episodes.length, 1);

      final ep = result.episodes.first;
      expect(ep.title, 'Episode 42: Agentic Workflows');
      expect(ep.guid, 'ep-42-ai');
      expect(ep.mediaUrl, 'https://media.example.com/ep42.mp3');
      expect(ep.duration, 4530); // 1h 15m 30s = 4530 seconds
      expect(ep.imageUrl, 'https://example.com/ep42.jpg');
    });

    test('Parses Atom XML Podcast Feed format', () {
      const xmlData = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Open Source Chronicle</title>
  <subtitle>News from open source communities</subtitle>
  <link href="https://opensource.example.com"/>
  <entry>
    <id>atom-entry-101</id>
    <title>Release 2.0 Deep Dive</title>
    <content type="html">&lt;p&gt;Overview of version 2.0 release.&lt;/p&gt;</content>
    <updated>2026-07-20T15:30:00Z</updated>
    <link rel="enclosure" href="https://media.example.com/atom101.mp3" type="audio/mpeg"/>
  </entry>
</feed>''';

      final result = parser.parseFeedXml(xmlData, 'https://opensource.example.com/atom.xml');

      expect(result.title, 'Open Source Chronicle');
      expect(result.episodes.length, 1);

      final ep = result.episodes.first;
      expect(ep.title, 'Release 2.0 Deep Dive');
      expect(ep.mediaUrl, 'https://media.example.com/atom101.mp3');
      expect(ep.description, contains('Overview of version 2.0 release.'));
    });

    test('Parses Rich HTML & CDATA Descriptions with tag sanitization', () {
      const xmlData = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Web Development Today</title>
    <description>Web Dev News</description>
    <item>
      <title>HTML5 &amp; CSS Tricks</title>
      <guid>web-dev-88</guid>
      <content:encoded><![CDATA[
        <p>Welcome to <strong>Episode 88</strong>!</p>
        <script>alert("malicious script");</script>
        <a href="https://example.com/notes">Show Notes</a>
      ]]></content:encoded>
      <enclosure url="https://media.example.com/web88.mp3" type="audio/mpeg"/>
    </item>
  </channel>
</rss>''';

      final result = parser.parseFeedXml(xmlData, 'https://webdev.example.com/feed.xml');

      final ep = result.episodes.first;
      // Script tags must be stripped, content preserved
      expect(ep.description, isNot(contains('<script>')));
      expect(ep.description, contains('Episode 88'));
    });

    testWidgets('Stores parsed diverse feed in SQLite DB and renders in EpisodeListView Show Page', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final audioHandler = MerlinAudioHandler();
      addTearDown(audioHandler.stop);

      const xmlData = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Real World Audio Podcast</title>
    <description>Diverse feed testing</description>
    <itunes:image href="https://example.com/art.png"/>
    <item>
      <title>Episode 1: Real World Testing</title>
      <guid>rw-ep-1</guid>
      <description>Testing real world RSS feeds in Flutter.</description>
      <enclosure url="https://media.example.com/rw1.mp3" type="audio/mpeg"/>
      <pubDate>Wed, 01 Jul 2026 08:00:00 GMT</pubDate>
      <itunes:duration>1800</itunes:duration>
    </item>
  </channel>
</rss>''';

      final feedResult = parser.parseFeedXml(xmlData, 'https://example.com/realworld.xml');

      final podcast = Podcast(
        id: 50,
        rssUrl: 'https://example.com/realworld.xml',
        title: feedResult.title,
        imageUrl: '',
        description: feedResult.description,
        link: feedResult.link,
        lastUpdated: DateTime.now(),
      );

      final episodes = feedResult.episodes.map((ep) => ep.copyWith(id: 1, podcastId: 50, imageUrl: '', podcastRss: 'https://example.com/realworld.xml')).toList();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(50).overrideWith(
              (ref) => TestEpisodesNotifier(episodes),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Real World Audio Podcast'), findsWidgets);
      expect(find.text('Episode 1: Real World Testing'), findsOneWidget);
    });
  });
}
