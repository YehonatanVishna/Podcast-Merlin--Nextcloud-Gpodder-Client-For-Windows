import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xml/xml.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/opml_service.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/episode_list_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/settings_view.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/timestamped_description.dart';

class MockAudioHandler extends MerlinAudioHandler {
  Episode? _testCurrentEpisode;
  Duration? lastSeekDuration;

  MockAudioHandler({DatabaseHelper? db}) : super(db: db ?? DatabaseHelper.instance, urlLoader: (_) async {});

  @override
  Episode? get currentEpisode => _testCurrentEpisode;

  @override
  Future<void> playEpisode(Episode episode) async {
    _testCurrentEpisode = episode;
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      updatePosition: Duration(seconds: episode.position),
    ));
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeekDuration = position;
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
    ));
  }
}

class FakeSecureStorageService extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _data[key];
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

base class FakePlatformFile extends PlatformFile {
  FakePlatformFile({
    required this.name,
    this.content = '',
    this.pathString,
  });

  @override
  final String name;

  final String content;
  final String? pathString;

  @override
  String? get path => pathString;

  @override
  Uri get uri => pathString != null ? Uri.file(pathString!) : Uri.parse('memory://$name');

  @override
  XFile get xFile => XFile.fromData(Uint8List.fromList(utf8.encode(content)), name: name);

  @override
  int? lengthSync() => utf8.encode(content).length;

  @override
  Future<int> length() async => utf8.encode(content).length;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(utf8.encode(content));

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List.fromList(utf8.encode(content)));
}

class FakeFilePickerPlatform extends FilePickerPlatform {
  List<PlatformFile> pickedFilesResult = [];
  Uri? saveFileResult;
  String? lastSavedFileName;
  Uint8List? lastSavedBytes;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return pickedFilesResult;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    lastSavedFileName = fileName;
    lastSavedBytes = bytes;
    return saveFileResult;
  }
}

class TestEpisodesNotifier extends StateNotifier<EpisodesState> implements EpisodesNotifier {
  bool toggleStarCalled = false;

  TestEpisodesNotifier(List<Episode> episodes, {EpisodeFilter filter = EpisodeFilter.all})
      : super(
          EpisodesState(
            episodes: episodes,
            isLoading: false,
            isLoadingMore: false,
            hasMore: false,
            filter: filter,
          ),
        );

  @override
  Future<void> loadEpisodes({EpisodeFilter? filter, bool silent = false}) async {}

  @override
  Future<void> loadMoreEpisodes() async {}

  @override
  Future<void> refresh({Podcast? podcast}) async {}

  @override
  Future<void> setFilter(EpisodeFilter filter) async {
    state = state.copyWith(filter: filter);
  }

  @override
  Future<bool> toggleStar(Episode episode) async {
    toggleStarCalled = true;
    if (!mounted || state.episodes.isEmpty) return false;
    final index = state.episodes.indexWhere((e) => e.guid == episode.guid);
    if (index != -1) {
      final updatedList = List<Episode>.from(state.episodes);
      final newStarred = !updatedList[index].isStarred;
      updatedList[index] = updatedList[index].copyWith(isStarred: newStarred);
      state = state.copyWith(episodes: updatedList);
      return newStarred;
    }
    return false;
  }

  @override
  void updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) {
    if (!mounted || state.episodes.isEmpty) return;
    final index = state.episodes.indexWhere((e) => e.mediaUrl == mediaUrl);
    if (index != -1) {
      final updatedList = List<Episode>.from(state.episodes);
      updatedList[index] = updatedList[index].copyWith(
        position: position,
        isPlayed: isPlayed,
      );
      state = state.copyWith(episodes: updatedList);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('subscription_backlog');
    await database.delete('playback_queue');
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');
  });

  // ===========================================================================
  // 1. OPML PARSER UNIT TESTS
  // ===========================================================================
  group('OPML Parser Unit Tests', () {
    test('parseOpml parses standard flat OPML with outlines, attributes, and text', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>My Subscriptions</title>
  </head>
  <body>
    <outline text="The Daily" title="The Daily" type="rss" xmlUrl="https://feeds.simplecast.com/thedaily" htmlUrl="https://nytimes.com/thedaily" description="This is what the day sounds like." />
    <outline text="Syntax FM" title="Syntax - Tasty Web Development Treats" type="rss" xmlUrl="https://feed.syntax.fm/rss" htmlUrl="https://syntax.fm" description="Full stack web development podcast." />
  </body>
</opml>''';

      final outlines = parseOpml(xml);
      expect(outlines.length, equals(2));

      expect(outlines[0].title, equals('The Daily'));
      expect(outlines[0].xmlUrl, equals('https://feeds.simplecast.com/thedaily'));
      expect(outlines[0].htmlUrl, equals('https://nytimes.com/thedaily'));
      expect(outlines[0].description, equals('This is what the day sounds like.'));
      expect(outlines[0].text, equals('The Daily'));

      expect(outlines[1].title, equals('Syntax - Tasty Web Development Treats'));
      expect(outlines[1].xmlUrl, equals('https://feed.syntax.fm/rss'));
      expect(outlines[1].htmlUrl, equals('https://syntax.fm'));
      expect(outlines[1].description, equals('Full stack web development podcast.'));
    });

    test('parseOpml parses nested outlines (folders/categories) recursively', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Nested Subscriptions</title>
  </head>
  <body>
    <outline text="Technology" title="Technology">
      <outline text="Syntax FM" type="rss" xmlUrl="https://feed.syntax.fm/rss" htmlUrl="https://syntax.fm" />
      <outline text="Security">
        <outline text="Darknet Diaries" type="rss" xmlUrl="https://feeds.megaphone.fm/darknetdiaries" htmlUrl="https://darknetdiaries.com" />
      </outline>
    </outline>
    <outline text="News" title="News">
      <outline text="The Daily" type="rss" xmlUrl="https://feeds.simplecast.com/thedaily" htmlUrl="https://nytimes.com/thedaily" />
    </outline>
  </body>
</opml>''';

      final outlines = parseOpml(xml);
      expect(outlines.length, equals(3));
      expect(outlines.map((o) => o.xmlUrl).toList(), containsAll([
        'https://feed.syntax.fm/rss',
        'https://feeds.megaphone.fm/darknetdiaries',
        'https://feeds.simplecast.com/thedaily',
      ]));
    });

    test('parseOpml handles attribute aliases and case insensitivity (xmlUrl, xmlurl, url)', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline title="Feed 1" xmlurl="https://example.com/feed1.xml" htmlurl="https://example.com/1" />
    <outline title="Feed 2" url="https://example.com/feed2.xml" />
  </body>
</opml>''';

      final outlines = parseOpml(xml);
      expect(outlines.length, equals(2));
      expect(outlines[0].xmlUrl, equals('https://example.com/feed1.xml'));
      expect(outlines[0].htmlUrl, equals('https://example.com/1'));
      expect(outlines[1].xmlUrl, equals('https://example.com/feed2.xml'));
    });

    test('parseOpml falls back between title and text attributes', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline text="Only Text Attribute" xmlUrl="https://example.com/text.xml" />
    <outline title="Only Title Attribute" xmlUrl="https://example.com/title.xml" />
  </body>
</opml>''';

      final outlines = parseOpml(xml);
      expect(outlines.length, equals(2));
      expect(outlines[0].title, equals('Only Text Attribute'));
      expect(outlines[0].text, equals('Only Text Attribute'));
      expect(outlines[1].title, equals('Only Title Attribute'));
      expect(outlines[1].text, equals('Only Title Attribute'));
    });

    test('parseOpml handles missing body tag gracefully', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <outline text="No Body Podcast" xmlUrl="https://example.com/nobody.xml" />
</opml>''';

      final outlines = parseOpml(xml);
      expect(outlines.length, equals(1));
      expect(outlines.first.title, equals('No Body Podcast'));
      expect(outlines.first.xmlUrl, equals('https://example.com/nobody.xml'));
    });

    test('parseOpml ignores outline nodes without a feed URL', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline text="Empty Category" />
    <outline text="Actual Feed" xmlUrl="https://example.com/feed.xml" />
  </body>
</opml>''';

      final outlines = parseOpml(xml);
      expect(outlines.length, equals(1));
      expect(outlines.first.title, equals('Actual Feed'));
    });

    test('parseOpml handles empty string, whitespace, and malformed XML gracefully', () {
      expect(parseOpml(''), isEmpty);
      expect(parseOpml('   \n\t  '), isEmpty);
      expect(parseOpml('This is completely not XML at all!'), isEmpty);
      expect(parseOpml('<opml><head><title>Unclosed Tag...'), isEmpty);
    });

    test('parseOpml handles XML entities and special characters', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline title="Tech &amp; Science &quot;Live&quot;" xmlUrl="https://example.com/feed.xml" description="News &amp; trends &lt;b&gt;today&lt;/b&gt;" />
  </body>
</opml>''';

      final outlines = parseOpml(xml);
      expect(outlines.length, equals(1));
      expect(outlines.first.title, equals('Tech & Science "Live"'));
      expect(outlines.first.description, equals('News & trends <b>today</b>'));
    });
  });

  // ===========================================================================
  // 2. OPML GENERATOR UNIT TESTS
  // ===========================================================================
  group('OPML Generator Unit Tests', () {
    test('generateOpml produces valid OPML 2.0 XML with correct structure and elements', () {
      final podcasts = [
        Podcast(
          id: 1,
          rssUrl: 'https://feeds.simplecast.com/thedaily',
          title: 'The Daily',
          description: 'This is what the day sounds like.',
          link: 'https://nytimes.com/thedaily',
          imageUrl: 'https://example.com/daily.jpg',
          lastUpdated: DateTime(2026, 3, 1),
        ),
        Podcast(
          id: 2,
          rssUrl: 'https://feed.syntax.fm/rss',
          title: 'Syntax FM',
          description: 'Tasty web dev treats.',
          link: 'https://syntax.fm',
          imageUrl: 'https://example.com/syntax.jpg',
          lastUpdated: DateTime(2026, 3, 2),
        ),
      ];

      final xmlString = generateOpml(podcasts: podcasts, title: 'Exported Feeds');

      // Verify valid XML parsing
      final doc = XmlDocument.parse(xmlString);
      expect(doc.rootElement.name.local, equals('opml'));
      expect(doc.rootElement.getAttribute('version'), equals('2.0'));

      final head = doc.rootElement.findElements('head').first;
      expect(head.findElements('title').first.innerText, equals('Exported Feeds'));
      expect(head.findElements('docs').first.innerText, equals('http://opml.org/spec2.opml'));

      final body = doc.rootElement.findElements('body').first;
      final outlines = body.findElements('outline').toList();
      expect(outlines.length, equals(2));

      expect(outlines[0].getAttribute('type'), equals('rss'));
      expect(outlines[0].getAttribute('title'), equals('The Daily'));
      expect(outlines[0].getAttribute('xmlUrl'), equals('https://feeds.simplecast.com/thedaily'));
      expect(outlines[0].getAttribute('htmlUrl'), equals('https://nytimes.com/thedaily'));
      expect(outlines[0].getAttribute('description'), equals('This is what the day sounds like.'));

      expect(outlines[1].getAttribute('type'), equals('rss'));
      expect(outlines[1].getAttribute('title'), equals('Syntax FM'));
      expect(outlines[1].getAttribute('xmlUrl'), equals('https://feed.syntax.fm/rss'));
    });

    test('generateOpml handles untitled podcasts and empty descriptions gracefully', () {
      final podcast = Podcast(
        rssUrl: 'https://example.com/notitle.xml',
        title: '',
        description: '',
        link: '',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      );

      final xmlString = generateOpml(podcasts: [podcast]);
      final doc = XmlDocument.parse(xmlString);
      final outline = doc.findAllElements('outline').first;

      expect(outline.getAttribute('title'), equals('Untitled Podcast'));
      expect(outline.getAttribute('text'), equals('Untitled Podcast'));
      expect(outline.getAttribute('description'), isNull);
    });

    test('generateOpml properly escapes special characters in titles & notes', () {
      final podcast = Podcast(
        rssUrl: 'https://example.com/feed.xml?a=1&b=2',
        title: 'Rock & Roll <Show> "Live"',
        description: 'Covers rock & roll, metal & blues.',
        link: 'https://example.com',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      );

      final xmlString = generateOpml(podcasts: [podcast]);
      expect(xmlString, contains('&amp;'));
      expect(xmlString, contains('&lt;Show>'));
      expect(xmlString, contains('&quot;Live&quot;'));

      final parsed = parseOpml(xmlString);
      expect(parsed.first.title, equals('Rock & Roll <Show> "Live"'));
      expect(parsed.first.xmlUrl, equals('https://example.com/feed.xml?a=1&b=2'));
    });

    test('round-trip: generateOpml output fed into parseOpml preserves all feeds', () {
      final originalPodcasts = [
        Podcast(
          id: 10,
          rssUrl: 'https://example.com/podcast1.xml',
          title: 'Podcast One',
          description: 'Description 1',
          link: 'https://example.com/p1',
          imageUrl: '',
          lastUpdated: DateTime.now(),
        ),
        Podcast(
          id: 11,
          rssUrl: 'https://example.com/podcast2.xml',
          title: 'Podcast Two',
          description: 'Description 2',
          link: 'https://example.com/p2',
          imageUrl: '',
          lastUpdated: DateTime.now(),
        ),
      ];

      final xmlString = generateOpml(podcasts: originalPodcasts);
      final outlines = parseOpml(xmlString);

      expect(outlines.length, equals(2));
      expect(outlines[0].title, equals('Podcast One'));
      expect(outlines[0].xmlUrl, equals('https://example.com/podcast1.xml'));
      expect(outlines[0].htmlUrl, equals('https://example.com/p1'));
      expect(outlines[0].description, equals('Description 1'));

      expect(outlines[1].title, equals('Podcast Two'));
      expect(outlines[1].xmlUrl, equals('https://example.com/podcast2.xml'));
      expect(outlines[1].htmlUrl, equals('https://example.com/p2'));
      expect(outlines[1].description, equals('Description 2'));
    });
  });

  // ===========================================================================
  // 3. OPML DATABASE IMPORT TESTS
  // ===========================================================================
  group('OPML Database Import Tests', () {
    test('importOpml inserts new podcasts into SQLite database and returns list', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline title="Imported Show 1" xmlUrl="https://example.com/import1.xml" htmlUrl="https://example.com/show1" description="Show 1 Notes" />
    <outline title="Imported Show 2" xmlUrl="https://example.com/import2.xml" htmlUrl="https://example.com/show2" description="Show 2 Notes" />
  </body>
</opml>''';

      final imported = await importOpml(xml, db, syncWithServer: false);
      expect(imported.length, equals(2));
      expect(imported[0].id, isNotNull);
      expect(imported[1].id, isNotNull);

      final dbPodcasts = await db.getAllPodcasts();
      expect(dbPodcasts.length, equals(2));
      expect(dbPodcasts.map((p) => p.rssUrl).toList(), containsAll([
        'https://example.com/import1.xml',
        'https://example.com/import2.xml',
      ]));
    });

    test('importOpml skips feeds already subscribed in the database', () async {
      final existingPod = Podcast(
        rssUrl: 'https://example.com/existing.xml',
        title: 'Already Subscribed',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      await db.insertPodcast(existingPod);

      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline title="Already Subscribed" xmlUrl="https://example.com/existing.xml" />
    <outline title="Brand New Show" xmlUrl="https://example.com/new.xml" />
  </body>
</opml>''';

      final imported = await importOpml(xml, db, syncWithServer: false);
      expect(imported.length, equals(1));
      expect(imported.first.title, equals('Brand New Show'));

      final allInDb = await db.getAllPodcasts();
      expect(allInDb.length, equals(2));
    });

    test('importOpml enqueues gPodder subscription backlog action when syncWithServer is true', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline title="Sync Show" xmlUrl="https://example.com/syncshow.xml" />
  </body>
</opml>''';

      final imported = await importOpml(xml, db, syncWithServer: true);
      expect(imported.length, equals(1));

      final pending = await db.getPendingSubscriptionChanges();
      final addList = List<String>.from(pending['add'] as Iterable);
      expect(addList, contains('https://example.com/syncshow.xml'));
    });

    test('importOpml does NOT enqueue gPodder backlog action when syncWithServer is false', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <body>
    <outline title="No Sync Show" xmlUrl="https://example.com/nosync.xml" />
  </body>
</opml>''';

      await importOpml(xml, db, syncWithServer: false);

      final pending = await db.getPendingSubscriptionChanges();
      final addList = List<String>.from(pending['add'] as Iterable);
      expect(addList, isEmpty);
    });

    test('importOpml handles empty or corrupt xml gracefully returning empty list', () async {
      final res1 = await importOpml('', db);
      final res2 = await importOpml('corrupted non xml', db);
      expect(res1, isEmpty);
      expect(res2, isEmpty);
      expect(await db.getAllPodcasts(), isEmpty);
    });
  });

  // ===========================================================================
  // 4. EPISODE STARRED STATE & DATABASE TESTS
  // ===========================================================================
  group('Episode Starred Database & Model Tests', () {
    test('Episode model defaults isStarred to false', () {
      final ep = Episode(
        guid: 'ep-default',
        title: 'Default Episode',
        description: '',
        mediaUrl: 'https://example.com/ep.mp3',
        imageUrl: '',
        podcastRss: 'https://example.com/rss.xml',
      );
      expect(ep.isStarred, isFalse);
    });

    test('Episode model copyWith properly updates isStarred', () {
      final ep = Episode(
        guid: 'ep-copy',
        title: 'Copy Episode',
        description: '',
        mediaUrl: 'https://example.com/ep.mp3',
        imageUrl: '',
        podcastRss: 'https://example.com/rss.xml',
        isStarred: false,
      );

      final starred = ep.copyWith(isStarred: true);
      expect(starred.isStarred, isTrue);

      final unstarred = starred.copyWith(isStarred: false);
      expect(unstarred.isStarred, isFalse);
    });

    test('Episode model toMap and fromMap persist isStarred correctly', () {
      final ep = Episode(
        id: 42,
        podcastId: 1,
        guid: 'ep-map',
        title: 'Map Episode',
        description: 'Notes',
        mediaUrl: 'https://example.com/ep.mp3',
        imageUrl: '',
        podcastRss: 'https://example.com/rss.xml',
        isStarred: true,
      );

      final map = ep.toMap();
      expect(map['isStarred'], equals(1));

      final restored = Episode.fromMap(map);
      expect(restored.isStarred, isTrue);

      final unstarredMap = ep.copyWith(isStarred: false).toMap();
      expect(unstarredMap['isStarred'], equals(0));
      expect(Episode.fromMap(unstarredMap).isStarred, isFalse);
    });

    test('DatabaseHelper setEpisodeStarred and toggleEpisodeStarred update SQLite', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/starred_test.xml',
        title: 'Starred Test Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/starred_test.xml',
        guid: 'starred-ep-1',
        title: 'Star Candidate',
        description: '',
        mediaUrl: 'https://example.com/cand.mp3',
        imageUrl: '',
        isStarred: false,
      );
      await db.insertEpisodes([ep]);

      final saved = (await db.getEpisodeByGuid('starred-ep-1'))!;
      expect(saved.isStarred, isFalse);

      // Explicit set to true
      await db.setEpisodeStarred(saved.id!, true);
      final afterSetTrue = (await db.getEpisodeByGuid('starred-ep-1'))!;
      expect(afterSetTrue.isStarred, isTrue);

      // Toggle to false
      final toggleRes1 = await db.toggleEpisodeStarred(saved.id!);
      expect(toggleRes1, isFalse);
      final afterToggleFalse = (await db.getEpisodeByGuid('starred-ep-1'))!;
      expect(afterToggleFalse.isStarred, isFalse);

      // Toggle back to true
      final toggleRes2 = await db.toggleEpisodeStarred(saved.id!);
      expect(toggleRes2, isTrue);
      final afterToggleTrue = (await db.getEpisodeByGuid('starred-ep-1'))!;
      expect(afterToggleTrue.isStarred, isTrue);
    });

    test('DatabaseHelper getStarredEpisodes retrieves only starred episodes across podcasts', () async {
      final pod1Id = await db.insertOrUpdatePodcast(Podcast(
        rssUrl: 'https://example.com/p1.xml',
        title: 'Show 1',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      ));
      final pod2Id = await db.insertOrUpdatePodcast(Podcast(
        rssUrl: 'https://example.com/p2.xml',
        title: 'Show 2',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      ));

      final eps = [
        Episode(
          podcastId: pod1Id,
          podcastRss: 'https://example.com/p1.xml',
          guid: 'p1-ep1',
          title: 'P1 Ep 1 (Starred)',
          description: '',
          mediaUrl: 'https://example.com/p1-1.mp3',
          imageUrl: '',
          publishedAt: DateTime(2026, 1, 10),
          isStarred: true,
        ),
        Episode(
          podcastId: pod1Id,
          podcastRss: 'https://example.com/p1.xml',
          guid: 'p1-ep2',
          title: 'P1 Ep 2 (Normal)',
          description: '',
          mediaUrl: 'https://example.com/p1-2.mp3',
          imageUrl: '',
          publishedAt: DateTime(2026, 1, 12),
          isStarred: false,
        ),
        Episode(
          podcastId: pod2Id,
          podcastRss: 'https://example.com/p2.xml',
          guid: 'p2-ep1',
          title: 'P2 Ep 1 (Starred newer)',
          description: '',
          mediaUrl: 'https://example.com/p2-1.mp3',
          imageUrl: '',
          publishedAt: DateTime(2026, 1, 15),
          isStarred: true,
        ),
      ];
      await db.insertEpisodes(eps);

      final starred = await db.getStarredEpisodes();
      expect(starred.length, equals(2));
      // Should be ordered by publishedAt DESC
      expect(starred[0].guid, equals('p2-ep1'));
      expect(starred[1].guid, equals('p1-ep1'));
      expect(starred.every((e) => e.isStarred), isTrue);
    });

    test('DatabaseHelper getEpisodesForPodcast and getAllEpisodes support EpisodeFilter.starred', () async {
      final podId = await db.insertOrUpdatePodcast(Podcast(
        rssUrl: 'https://example.com/p.xml',
        title: 'Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      ));

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          podcastRss: 'https://example.com/p.xml',
          guid: 'star-1',
          title: 'Star 1',
          description: '',
          mediaUrl: 'https://example.com/s1.mp3',
          imageUrl: '',
          isStarred: true,
        ),
        Episode(
          podcastId: podId,
          podcastRss: 'https://example.com/p.xml',
          guid: 'unstar-2',
          title: 'Unstar 2',
          description: '',
          mediaUrl: 'https://example.com/s2.mp3',
          imageUrl: '',
          isStarred: false,
        ),
      ]);

      final podcastStarred = await db.getEpisodesForPodcast(podId, filter: EpisodeFilter.starred);
      expect(podcastStarred.length, equals(1));
      expect(podcastStarred.first.guid, equals('star-1'));

      final allStarred = await db.getAllEpisodes(filter: EpisodeFilter.starred);
      expect(allStarred.length, equals(1));
      expect(allStarred.first.guid, equals('star-1'));
    });
  });

  // ===========================================================================
  // 5. TIMESTAMP PARSING & UTILITIES TESTS
  // ===========================================================================
  group('Timestamp Parsing & Utilities Unit Tests', () {
    test('parseTimestampToDuration correctly converts MM:SS', () {
      expect(parseTimestampToDuration('05:30'), equals(const Duration(minutes: 5, seconds: 30)));
      expect(parseTimestampToDuration('00:45'), equals(const Duration(seconds: 45)));
      expect(parseTimestampToDuration('59:59'), equals(const Duration(minutes: 59, seconds: 59)));
      expect(parseTimestampToDuration('1:05'), equals(const Duration(minutes: 1, seconds: 5)));
    });

    test('parseTimestampToDuration correctly converts H:MM:SS and HH:MM:SS', () {
      expect(parseTimestampToDuration('1:15:30'), equals(const Duration(hours: 1, minutes: 15, seconds: 30)));
      expect(parseTimestampToDuration('02:00:00'), equals(const Duration(hours: 2)));
      expect(parseTimestampToDuration('10:05:25'), equals(const Duration(hours: 10, minutes: 5, seconds: 25)));
    });

    test('parseTimestampToDuration handles surrounding text and invalid strings', () {
      expect(parseTimestampToDuration('at 05:30 in episode'), equals(const Duration(minutes: 5, seconds: 30)));
      expect(parseTimestampToDuration('non-timestamp-string'), equals(Duration.zero));
      expect(parseTimestampToDuration(''), equals(Duration.zero));
    });

    test('extractTimestamps extracts all valid timestamps in order', () {
      const notes = '''
      Show Notes:
      - 00:00 Introduction
      - 05:30 Segment 1: The Basics
      - 1:15:20 Deep Dive
      - 02:00:00 Q&A and wrap up
      ''';

      final timestamps = extractTimestamps(notes);
      expect(timestamps, equals(['00:00', '05:30', '1:15:20', '02:00:00']));
    });

    test('stripHtmlTags strips tags and unescapes common entities', () {
      const html = '<p>Welcome to <b>Podcast Merlin</b>!<br/>Today we talk &amp; learn.<br />Visit <a href="https://example.com">here</a> &quot;soon&quot;.</p>';
      final stripped = stripHtmlTags(html);
      expect(stripped, contains('Welcome to Podcast Merlin!'));
      expect(stripped, contains('Today we talk & learn.'));
      expect(stripped, contains('Visit here "soon".'));
      expect(stripped, isNot(contains('<p>')));
      expect(stripped, isNot(contains('<b>')));
      expect(stripped, isNot(contains('&amp;')));
    });
  });

  // ===========================================================================
  // 6. EPISODELISTVIEW SEARCH & FILTER CHIP WIDGET TESTS
  // ===========================================================================
  group('EpisodeListView Search & Filter Chip Widget Tests', () {
    final podcast = Podcast(
      id: 1,
      rssUrl: 'https://example.com/podcast.xml',
      title: 'Filter & Search Podcast',
      description: '',
      imageUrl: '',
      link: '',
      lastUpdated: DateTime.now(),
    );

    final episodes = [
      Episode(
        id: 101,
        podcastId: 1,
        podcastRss: 'https://example.com/podcast.xml',
        guid: 'ep-flutter',
        title: 'Building with Flutter',
        description: 'All about state management and widgets.',
        mediaUrl: 'https://example.com/flutter.mp3',
        publishedAt: DateTime(2026, 3, 1),
        duration: 1800,
        position: 0,
        isPlayed: false,
        isStarred: false,
        imageUrl: '',
      ),
      Episode(
        id: 102,
        podcastId: 1,
        podcastRss: 'https://example.com/podcast.xml',
        guid: 'ep-dart',
        title: 'Deep Dive into Dart',
        description: 'Async streams and records in Dart 3.',
        mediaUrl: 'https://example.com/dart.mp3',
        publishedAt: DateTime(2026, 3, 2),
        duration: 2000,
        position: 600, // In progress
        isPlayed: false,
        isStarred: true, // Starred
        imageUrl: '',
      ),
      Episode(
        id: 103,
        podcastId: 1,
        podcastRss: 'https://example.com/podcast.xml',
        guid: 'ep-arch',
        title: 'Mobile Architecture',
        description: 'Clean architecture and testing techniques.',
        mediaUrl: 'https://example.com/arch.mp3',
        publishedAt: DateTime(2026, 3, 3),
        duration: 1500,
        position: 1500,
        isPlayed: true, // Finished
        isStarred: false,
        imageUrl: '',
      ),
    ];

    testWidgets('Renders search TextField, filter chips, and showing count badge', (tester) async {
      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier(episodes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search field hint
      expect(find.text('Search episodes by title or notes...'), findsOneWidget);

      // Filter chips
      expect(find.byKey(const ValueKey('filter_all')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_unplayed')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_in_progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_starred')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter_downloaded')), findsOneWidget);

      // Episode count badge
      expect(find.text('Showing 3 of 3 episodes'), findsOneWidget);

      // All 3 episode titles visible
      expect(find.text('Building with Flutter'), findsOneWidget);
      expect(find.text('Deep Dive into Dart'), findsOneWidget);
      expect(find.text('Mobile Architecture'), findsOneWidget);
    });

    testWidgets('Searching by title filters the episode list in real-time', (tester) async {
      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier(episodes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter "flutter" into search TextField
      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pumpAndSettle();

      // Count badge updates
      expect(find.text('Showing 1 of 3 episodes'), findsOneWidget);

      // Only Flutter episode visible
      expect(find.text('Building with Flutter'), findsOneWidget);
      expect(find.text('Deep Dive into Dart'), findsNothing);
      expect(find.text('Mobile Architecture'), findsNothing);

      // Clear search button appears
      expect(find.byIcon(Icons.clear), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // All episodes restored
      expect(find.text('Showing 3 of 3 episodes'), findsOneWidget);
      expect(find.text('Deep Dive into Dart'), findsOneWidget);
    });

    testWidgets('Searching by description filters episode list', (tester) async {
      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier(episodes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search for word in description: "records"
      await tester.enterText(find.byType(TextField), 'records');
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 of 3 episodes'), findsOneWidget);
      expect(find.text('Deep Dive into Dart'), findsOneWidget);
      expect(find.text('Building with Flutter'), findsNothing);
    });

    testWidgets('Tapping Starred filter chip filters to only starred episodes', (tester) async {
      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier(episodes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Starred" chip
      await tester.tap(find.byKey(const ValueKey('filter_starred')));
      await tester.pumpAndSettle();

      // Only ep-dart is starred
      expect(find.text('Showing 1 of 3 episodes'), findsOneWidget);
      expect(find.text('Deep Dive into Dart'), findsOneWidget);
      expect(find.text('Building with Flutter'), findsNothing);
      expect(find.text('Mobile Architecture'), findsNothing);
    });

    testWidgets('Tapping In Progress filter chip filters to episodes in progress', (tester) async {
      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier(episodes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "In Progress" chip
      await tester.tap(find.byKey(const ValueKey('filter_in_progress')));
      await tester.pumpAndSettle();

      // Only ep-dart has position > 0 and is not finished
      expect(find.text('Showing 1 of 3 episodes'), findsOneWidget);
      expect(find.text('Deep Dive into Dart'), findsOneWidget);
      expect(find.text('Building with Flutter'), findsNothing);
    });

    testWidgets('Tapping Unplayed filter chip hides finished episodes', (tester) async {
      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier(episodes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Unplayed" chip
      await tester.tap(find.byKey(const ValueKey('filter_unplayed')));
      await tester.pumpAndSettle();

      // Flutter and Dart should be shown (neither is finished/isPlayed)
      expect(find.text('Showing 2 of 3 episodes'), findsOneWidget);
      expect(find.text('Building with Flutter'), findsOneWidget);
      expect(find.text('Deep Dive into Dart'), findsOneWidget);
      expect(find.text('Mobile Architecture'), findsNothing);
    });

    testWidgets('Empty search results renders empty state with Clear Filters button', (tester) async {
      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier(episodes);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Search non-existent string
      await tester.enterText(find.byType(TextField), 'nonexistent_xyz');
      await tester.pumpAndSettle();

      expect(find.text('Showing 0 of 3 episodes'), findsOneWidget);
      expect(find.text('No episodes match your search / filter'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);

      // Tap "Clear Filters"
      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();

      // List is restored
      expect(find.text('Showing 3 of 3 episodes'), findsOneWidget);
      expect(find.text('Building with Flutter'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 7. EPISODE STAR INTERACTIVITY WIDGET TESTS
  // ===========================================================================
  group('Episode Star Interactivity Widget Tests', () {
    final podcast = Podcast(
      id: 1,
      rssUrl: 'https://example.com/podcast.xml',
      title: 'Star Interactivity Podcast',
      description: '',
      imageUrl: '',
      link: '',
      lastUpdated: DateTime.now(),
    );

    testWidgets('_EpisodeTile renders star icon and toggles star on tap', (tester) async {
      final unstarredEp = Episode(
        id: 201,
        podcastId: 1,
        podcastRss: 'https://example.com/podcast.xml',
        guid: 'ep-toggle-star',
        title: 'Star Toggle Target',
        description: '',
        mediaUrl: 'https://example.com/star.mp3',
        publishedAt: DateTime(2026, 3, 1),
        isStarred: false,
        imageUrl: '',
      );

      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier([unstarredEp]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: podcast),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially unstarred: star_border icon
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);

      // Tap star button
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      // Notifier toggleStar called, state updated to starred
      expect(notifier.toggleStarCalled, isTrue);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNothing);
    });

    testWidgets('Episode details bottom sheet allows toggling star with feedback', (tester) async {
      final episode = Episode(
        id: 202,
        podcastId: 1,
        podcastRss: 'https://example.com/podcast.xml',
        guid: 'ep-sheet-star',
        title: 'Sheet Star Episode',
        description: 'Episode notes with timestamp 04:15 for testing.',
        mediaUrl: 'https://example.com/sheet.mp3',
        publishedAt: DateTime(2026, 3, 1),
        isStarred: false,
        imageUrl: '',
      );

      final audioHandler = MockAudioHandler(db: db);
      final notifier = TestEpisodesNotifier([episode]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EpisodeListView(podcast: podcast),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap episode tile to open details modal
      await tester.tap(find.text('Sheet Star Episode'));
      await tester.pumpAndSettle();

      // Verify Star Episode button in bottom sheet
      expect(find.text('Star Episode'), findsOneWidget);

      // Tap Star Episode button
      await tester.tap(find.text('Star Episode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // SnackBar shows "Episode starred"
      expect(find.text('Episode starred'), findsOneWidget);
      expect(notifier.toggleStarCalled, isTrue);

      // Settle any remaining snackbar timer
      await tester.pump(const Duration(seconds: 3));
    });
  });

  // ===========================================================================
  // 8. TIMESTAMPED DESCRIPTION WIDGET TESTS
  // ===========================================================================
  group('TimestampedDescription Widget Tests', () {
    testWidgets('Renders timestamps as clickable quick chips and triggers seek callback', (tester) async {
      Duration? tappedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimestampedDescription(
              text: 'In this episode: Introduction at 02:30, Deep Dive at 15:45, Wrap-up at 1:02:10.',
              onSeek: (dur) => tappedDuration = dur,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Quick chapter chips at top
      expect(find.text('02:30'), findsWidgets);
      expect(find.text('15:45'), findsWidgets);
      expect(find.text('1:02:10'), findsWidgets);

      // Tap 02:30 chip
      await tester.tap(find.text('02:30').first);
      await tester.pumpAndSettle();

      expect(tappedDuration, equals(const Duration(minutes: 2, seconds: 30)));
      expect(find.text('Seeking to 02:30'), findsOneWidget);

      // Clean up SnackBar timer
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Renders plain selectable text when no timestamps present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TimestampedDescription(
              text: 'Plain episode description with no timestamps whatsoever.',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Plain episode description with no timestamps whatsoever.'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 9. SETTINGSVIEW OPML MANAGEMENT DIALOG TESTS
  // ===========================================================================
  group('SettingsView OPML Dialogs Widget Tests', () {
    testWidgets('SettingsView displays OPML section with Export and Import buttons', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final audioHandler = MockAudioHandler(db: db);
      final fakeStorage = FakeSecureStorageService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            secureStorageProvider.overrideWithValue(fakeStorage),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      // Pump to let async credentials loader finish and update _isLoading = false
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('OPML Management'), findsOneWidget);
      expect(find.text('Export OPML'), findsOneWidget);
      expect(find.text('Import OPML'), findsOneWidget);
    });

    testWidgets('Tapping Export OPML triggers native file save and displays feedback snackbar', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final originalPicker = FilePickerPlatform.instance;
      final fakePicker = FakeFilePickerPlatform();
      fakePicker.saveFileResult = Uri.file('/tmp/exported_podcasts.opml');
      FilePickerPlatform.instance = fakePicker;
      addTearDown(() {
        FilePickerPlatform.instance = originalPicker;
      });

      final testPodcast = Podcast(
        rssUrl: 'https://example.com/export_test.xml',
        title: 'Exported Podcast',
        description: 'Testing export to file',
        imageUrl: '',
        link: 'https://example.com/export_test',
        lastUpdated: DateTime.now(),
      );
      await tester.runAsync(() async {
        await db.insertOrUpdatePodcast(testPodcast);
      });

      final audioHandler = MockAudioHandler(db: db);
      final fakeStorage = FakeSecureStorageService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            secureStorageProvider.overrideWithValue(fakeStorage),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final exportBtn = find.text('Export OPML');
      await tester.tap(exportBtn);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Verify file picker saveFile was called with OPML XML bytes
      expect(fakePicker.lastSavedFileName, equals('subscriptions.opml'));
      expect(fakePicker.lastSavedBytes, isNotNull);
      final xmlString = utf8.decode(fakePicker.lastSavedBytes!);
      expect(xmlString, contains('Exported Podcast'));
      expect(xmlString, contains('https://example.com/export_test.xml'));

      // Verify success SnackBar was shown with saved file name
      expect(find.textContaining('Exported'), findsOneWidget);
      expect(find.textContaining('exported_podcasts.opml'), findsOneWidget);
    });

    testWidgets('Tapping Import OPML displays file preview dialog and imports feeds into database', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final originalPicker = FilePickerPlatform.instance;
      final fakePicker = FakeFilePickerPlatform();
      const opmlContent = '''
<opml version="2.0">
  <head><title>Test Feeds</title></head>
  <body>
    <outline text="File Feed Show" title="File Feed Show" xmlUrl="https://example.com/filefeed.xml" htmlUrl="https://example.com" />
  </body>
</opml>''';
      fakePicker.pickedFilesResult = [
        FakePlatformFile(name: 'my_subscriptions.opml', content: opmlContent),
      ];
      FilePickerPlatform.instance = fakePicker;
      addTearDown(() {
        FilePickerPlatform.instance = originalPicker;
      });

      final audioHandler = MockAudioHandler(db: db);
      final fakeStorage = FakeSecureStorageService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            secureStorageProvider.overrideWithValue(fakeStorage),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final importBtn = find.text('Import OPML');
      await tester.tap(importBtn);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify file-based preview and confirmation dialog
      expect(find.text('Import Subscriptions'), findsOneWidget);
      expect(find.text('my_subscriptions.opml'), findsOneWidget);
      expect(find.textContaining('Found 1 podcast subscription'), findsOneWidget);
      expect(find.text('File Feed Show'), findsOneWidget);
      expect(find.text('https://example.com/filefeed.xml'), findsOneWidget);
      expect(find.text('Sync new feeds with gPodder'), findsOneWidget);
      expect(find.text('Import (1)'), findsOneWidget);

      // Confirm import
      await tester.tap(find.text('Import (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // Dialog dismisses and returns

      // Allow background SQLite and Riverpod async tasks to process
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        if (find.textContaining('Successfully imported').evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 300));

      // Verify dialog dismissed and success feedback shown
      expect(find.text('Import Subscriptions'), findsNothing);
      expect(
        find.textContaining('Successfully imported 1 podcast(s) from "my_subscriptions.opml"'),
        findsOneWidget,
      );

      // Verify database updated with new podcast
      Podcast? savedInDb;
      await tester.runAsync(() async {
        savedInDb = await db.getPodcastByUrl('https://example.com/filefeed.xml');
      });
      expect(savedInDb, isNotNull);
      expect(savedInDb!.title, equals('File Feed Show'));
    });

    testWidgets('Tapping Import OPML and canceling dialog does not import feeds', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final originalPicker = FilePickerPlatform.instance;
      final fakePicker = FakeFilePickerPlatform();
      const opmlContent = '''
<opml version="2.0">
  <body>
    <outline title="Cancelled Feed" xmlUrl="https://example.com/cancelled.xml" />
  </body>
</opml>''';
      fakePicker.pickedFilesResult = [
        FakePlatformFile(name: 'cancel_test.opml', content: opmlContent),
      ];
      FilePickerPlatform.instance = fakePicker;
      addTearDown(() {
        FilePickerPlatform.instance = originalPicker;
      });

      final audioHandler = MockAudioHandler(db: db);
      final fakeStorage = FakeSecureStorageService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            secureStorageProvider.overrideWithValue(fakeStorage),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final importBtn = find.text('Import OPML');
      await tester.tap(importBtn);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Import Subscriptions'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Import Subscriptions'), findsNothing);
      Podcast? notInDb;
      await tester.runAsync(() async {
        notInDb = await db.getPodcastByUrl('https://example.com/cancelled.xml');
      });
      expect(notInDb, isNull);
    });
  });
}
