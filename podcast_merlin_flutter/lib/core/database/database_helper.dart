import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_path.dart';
import 'ffi_init.dart';
import '../models/podcast.dart';
import '../models/episode.dart';
import '../models/gpodder_action.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Completer<Database>? _dbInitCompleter;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_dbInitCompleter != null) return _dbInitCompleter!.future;

    _dbInitCompleter = Completer<Database>();
    try {
      _database = await _initDB('podcast_merlin.db');
      _dbInitCompleter!.complete(_database!);
      return _database!;
    } catch (e, stack) {
      _dbInitCompleter!.completeError(e, stack);
      _dbInitCompleter = null;
      rethrow;
    }
  }

  String _podcastIdCol = 'podcastId';
  String _pubDateCol = 'pubDate';
  String _isPlayedCol = 'isPlayed';
  String _mediaUrlCol = 'mediaUrl';
  String _podcastRssUrlCol = 'rssUrl';

  Future<void> _detectColumnNames(Database db) async {
    try {
      final episodeInfo = await db.rawQuery('PRAGMA table_info(episodes)');
      final epCols = episodeInfo.map((row) => row['name'].toString()).toSet();

      if (epCols.contains('podcastId')) {
        _podcastIdCol = 'podcastId';
      } else if (epCols.contains('podcast_id')) {
        _podcastIdCol = 'podcast_id';
      }

      if (epCols.contains('pubDate')) {
        _pubDateCol = 'pubDate';
      } else if (epCols.contains('pub_date')) {
        _pubDateCol = 'pub_date';
      } else if (epCols.contains('published_at')) {
        _pubDateCol = 'published_at';
      }

      if (epCols.contains('isPlayed')) {
        _isPlayedCol = 'isPlayed';
      } else if (epCols.contains('is_played')) {
        _isPlayedCol = 'is_played';
      }

      if (epCols.contains('mediaUrl')) {
        _mediaUrlCol = 'mediaUrl';
      } else if (epCols.contains('media_url')) {
        _mediaUrlCol = 'media_url';
      }

      final podcastInfo = await db.rawQuery('PRAGMA table_info(podcasts)');
      final podCols = podcastInfo.map((row) => row['name'].toString()).toSet();
      if (podCols.contains('rssUrl')) {
        _podcastRssUrlCol = 'rssUrl';
      } else if (podCols.contains('rss_url')) {
        _podcastRssUrlCol = 'rss_url';
      }

      if (!podCols.contains('isDead') && !podCols.contains('is_dead')) {
        try {
          await db.execute('ALTER TABLE podcasts ADD COLUMN isDead INTEGER DEFAULT 0;');
        } catch (_) {}
      }
      if (!podCols.contains('lastFeedError') && !podCols.contains('last_feed_error')) {
        try {
          await db.execute('ALTER TABLE podcasts ADD COLUMN lastFeedError TEXT;');
        } catch (_) {}
      }
      if (!podCols.contains('feedErrorCount') && !podCols.contains('feed_error_count')) {
        try {
          await db.execute('ALTER TABLE podcasts ADD COLUMN feedErrorCount INTEGER DEFAULT 0;');
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<Database> _initDB(String filePath) async {
    // 1. Initialize FFI setup first on desktop/mobile
    setupFfi();

    final db = kIsWeb
        ? await openDatabase(
            filePath,
            version: 1,
            onConfigure: (db) async {
              await db.execute('PRAGMA foreign_keys = ON;');
            },
            onCreate: _createDB,
          )
        : await openDatabase(
            await getDatabasePath(filePath),
            version: 1,
            onConfigure: (db) async {
              await db.execute('PRAGMA foreign_keys = ON;');
            },
            onCreate: _createDB,
          );

    await _detectColumnNames(db);
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE podcasts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rssUrl TEXT UNIQUE NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        imageUrl TEXT,
        websiteUrl TEXT,
        lastUpdated TEXT,
        isDead INTEGER DEFAULT 0,
        lastFeedError TEXT,
        feedErrorCount INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE episodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        podcastId INTEGER NOT NULL,
        guid TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        mediaUrl TEXT NOT NULL,
        pubDate TEXT,
        duration INTEGER,
        position INTEGER DEFAULT 0,
        isPlayed INTEGER DEFAULT 0,
        imageUrl TEXT,
        FOREIGN KEY (podcastId) REFERENCES podcasts (id) ON DELETE CASCADE,
        UNIQUE (podcastId, guid)
      )
    ''');

    await db.execute('''
      CREATE TABLE gpodder_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        podcast TEXT,
        episode TEXT,
        action TEXT NOT NULL,
        position INTEGER,
        started INTEGER,
        total INTEGER,
        device TEXT,
        status TEXT,
        timestamp TEXT NOT NULL,
        podcastUrl TEXT,
        episodeUrl TEXT,
        totalDuration INTEGER
      )
    ''');
  }

  // PODCAST CRUD OPERATIONS

  Future<int> insertPodcast(Podcast podcast) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.insert(
      'podcasts',
      podcast.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertOrUpdatePodcast(Podcast podcast) async => insertPodcast(podcast);

  Future<List<Podcast>> getAllPodcasts() async {
    final db = await instance.database;
    final maps = await db.query('podcasts', orderBy: 'title ASC');
    return maps.map((map) => Podcast.fromMap(map)).toList();
  }

  Future<Podcast?> getPodcastByUrl(String rssUrl) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final maps = await db.query(
      'podcasts',
      where: '$_podcastRssUrlCol = ?',
      whereArgs: [rssUrl],
    );
    if (maps.isNotEmpty) {
      return Podcast.fromMap(maps.first);
    }
    return null;
  }

  Future<Podcast?> getPodcastByRssUrl(String rssUrl) async => getPodcastByUrl(rssUrl);

  Future<int> deletePodcast(int id) async {
    final db = await instance.database;
    return db.delete(
      'podcasts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePodcastByUrl(String rssUrl) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.delete(
      'podcasts',
      where: '$_podcastRssUrlCol = ?',
      whereArgs: [rssUrl],
    );
  }

  Future<void> markPodcastDead(String rssUrl, String errorMessage) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final existing = await getPodcastByRssUrl(rssUrl);
    final currentCount = existing?.feedErrorCount ?? 0;
    await db.update(
      'podcasts',
      {
        'isDead': 1,
        'lastFeedError': errorMessage,
        'feedErrorCount': currentCount + 1,
      },
      where: '$_podcastRssUrlCol = ?',
      whereArgs: [rssUrl],
    );
  }

  Future<void> markPodcastHealthy(String rssUrl) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    await db.update(
      'podcasts',
      {
        'isDead': 0,
        'lastFeedError': null,
        'feedErrorCount': 0,
      },
      where: '$_podcastRssUrlCol = ?',
      whereArgs: [rssUrl],
    );
  }

  Future<List<Podcast>> getDeadPodcasts() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final maps = await db.query(
      'podcasts',
      where: 'isDead = 1 OR lastFeedError IS NOT NULL',
    );
    return maps.map((m) => Podcast.fromMap(m)).toList();
  }

  // EPISODE CRUD OPERATIONS

  Future<void> insertEpisodes(List<Episode> episodes) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final batch = db.batch();
    for (final episode in episodes) {
      final map = episode.toMap();
      final adaptedMap = <String, dynamic>{
        if (map.containsKey('id')) 'id': map['id'],
        _podcastIdCol: episode.podcastId,
        'guid': episode.guid,
        'title': episode.title,
        'description': episode.description,
        _mediaUrlCol: episode.mediaUrl,
        _pubDateCol: episode.publishedAt?.toIso8601String(),
        'duration': episode.duration,
        'position': episode.position,
        _isPlayedCol: episode.isPlayed ? 1 : 0,
        'imageUrl': episode.imageUrl,
      };
      batch.insert(
        'episodes',
        adaptedMap,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Podcast?> getPodcastById(int id) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final maps = await db.query(
      'podcasts',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Podcast.fromMap(maps.first);
    }
    return null;
  }

  Future<void> saveEpisodesBatch(List<Episode> episodes) async => insertEpisodes(episodes);

  Future<List<Episode>> getEpisodesForPodcast(
    int podcastId, {
    int? limit,
    int? offset,
    EpisodeFilter filter = EpisodeFilter.all,
  }) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    String whereClause = 'e.$_podcastIdCol = ?';
    List<dynamic> whereArgs = [podcastId];

    if (filter == EpisodeFilter.unplayed) {
      whereClause += ' AND e.$_isPlayedCol = 0 AND (e.duration IS NULL OR e.duration = 0 OR e.position < (e.duration - 10))';
    } else if (filter == EpisodeFilter.finished) {
      whereClause += ' AND (e.$_isPlayedCol = 1 OR (e.duration IS NOT NULL AND e.duration > 0 AND e.position >= (e.duration - 10)))';
    }

    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
      WHERE $whereClause
      ORDER BY e.$_pubDateCol DESC
      ${limit != null ? 'LIMIT $limit' : ''}
      ${offset != null ? 'OFFSET $offset' : ''}
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<List<Episode>> getAllEpisodes({
    int? limit,
    int? offset,
    EpisodeFilter filter = EpisodeFilter.all,
  }) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (filter == EpisodeFilter.unplayed) {
      whereClause = 'e.$_isPlayedCol = 0 AND (e.duration IS NULL OR e.duration = 0 OR e.position < (e.duration - 10))';
    } else if (filter == EpisodeFilter.finished) {
      whereClause = '(e.$_isPlayedCol = 1 OR (e.duration IS NOT NULL AND e.duration > 0 AND e.position >= (e.duration - 10)))';
    }

    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
      WHERE $whereClause
      ORDER BY e.$_pubDateCol DESC
      ${limit != null ? 'LIMIT $limit' : ''}
      ${offset != null ? 'OFFSET $offset' : ''}
    ''';

    final maps = await db.rawQuery(query, whereArgs);
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<List<Episode>> getAllUnplayedEpisodes() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
      WHERE e.$_isPlayedCol = 0
      ORDER BY e.$_pubDateCol DESC
    ''';
    final maps = await db.rawQuery(query);
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<Episode?> getEpisodeByMediaUrl(String mediaUrl) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
      WHERE e.$_mediaUrlCol = ?
    ''';
    final maps = await db.rawQuery(query, [mediaUrl]);
    if (maps.isNotEmpty) {
      return Episode.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.update(
      'episodes',
      {
        'position': position,
        _isPlayedCol: isPlayed ? 1 : 0,
      },
      where: '$_mediaUrlCol = ?',
      whereArgs: [mediaUrl],
    );
  }

  Future<int> updateEpisodePlaybackState(String mediaUrl, int position, {bool isPlayed = false}) async =>
      updateEpisodeProgress(mediaUrl, position, isPlayed);

  // GPODDER OFFLINE ACTION QUEUE

  Future<int> queueGPodderAction(GPodderAction action) async {
    final db = await instance.database;
    final info = await db.rawQuery('PRAGMA table_info(gpodder_actions)');
    final cols = info.map((row) => row['name'].toString()).toSet();

    final map = action.toMap();
    final adapted = <String, dynamic>{};
    for (final entry in map.entries) {
      if (cols.contains(entry.key)) {
        adapted[entry.key] = entry.value;
      }
    }

    if (cols.contains('podcastUrl')) {
      adapted['podcastUrl'] = action.podcast;
    }
    if (cols.contains('episodeUrl')) {
      adapted['episodeUrl'] = action.episode;
    }
    if (cols.contains('totalDuration')) {
      adapted['totalDuration'] = action.total;
    }

    return db.insert('gpodder_actions', adapted);
  }

  Future<int> enqueueAction(GPodderAction action) async => queueGPodderAction(action);

  Future<List<GPodderAction>> getQueuedGPodderActions() async {
    final db = await instance.database;
    final maps = await db.query('gpodder_actions', orderBy: 'id ASC');

    final actions = maps.map((m) => GPodderAction.fromMap(m)).toList();
    return collapseActions(actions);
  }

  Future<List<GPodderAction>> getPendingActions() async => getQueuedGPodderActions();

  /// Collapse duplicate play actions for the same episode chronologically
  List<GPodderAction> collapseActions(List<GPodderAction> actions) {
    final Map<String, GPodderAction> collapsedMap = {};
    final List<GPodderAction> nonPlayActions = [];

    for (final action in actions) {
      if (action.action == 'play') {
        final key = '${action.podcastFeedUrl}|${action.episodeMediaUrl}';
        if (!collapsedMap.containsKey(key)) {
          collapsedMap[key] = action;
        } else {
          final existing = collapsedMap[key]!;
          if (action.timestamp.isAfter(existing.timestamp)) {
            collapsedMap[key] = action;
          }
        }
      } else {
        nonPlayActions.add(action);
      }
    }

    final result = [...collapsedMap.values, ...nonPlayActions];
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<int> clearQueuedGPodderActionsUpTo(int maxId) async {
    final db = await instance.database;
    return db.delete(
      'gpodder_actions',
      where: 'id <= ?',
      whereArgs: [maxId],
    );
  }

  Future<int> markActionsSynced(dynamic actionsOrIds) async {
    if (actionsOrIds is List<int>) {
      if (actionsOrIds.isEmpty) return 0;
      final maxId = actionsOrIds.fold(0, (prev, curr) => curr > prev ? curr : prev);
      return clearQueuedGPodderActionsUpTo(maxId);
    } else if (actionsOrIds is List<GPodderAction>) {
      if (actionsOrIds.isEmpty) return 0;
      final maxId = actionsOrIds.map((a) => a.id ?? 0).fold(0, (prev, curr) => curr > prev ? curr : prev);
      return clearQueuedGPodderActionsUpTo(maxId);
    }
    return 0;
  }
}
