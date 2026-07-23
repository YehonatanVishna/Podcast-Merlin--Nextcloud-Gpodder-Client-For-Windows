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
        lastUpdated TEXT
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
        podcastUrl TEXT NOT NULL,
        episodeUrl TEXT NOT NULL,
        action TEXT NOT NULL,
        position INTEGER,
        totalDuration INTEGER,
        timestamp TEXT NOT NULL
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

  Future<void> saveEpisodesBatch(List<Episode> episodes) async => insertEpisodes(episodes);

  Future<List<Episode>> getEpisodesForPodcast(
    int podcastId, {
    int? limit,
    int? offset,
    EpisodeFilter filter = EpisodeFilter.all,
  }) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    String whereClause = '$_podcastIdCol = ?';
    List<dynamic> whereArgs = [podcastId];

    if (filter == EpisodeFilter.unplayed) {
      whereClause += ' AND $_isPlayedCol = 0 AND (duration IS NULL OR duration = 0 OR position < (duration - 10))';
    } else if (filter == EpisodeFilter.finished) {
      whereClause += ' AND ($_isPlayedCol = 1 OR (duration IS NOT NULL AND duration > 0 AND position >= (duration - 10)))';
    }

    final maps = await db.query(
      'episodes',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '$_pubDateCol DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<List<Episode>> getAllEpisodes({
    int? limit,
    int? offset,
    EpisodeFilter filter = EpisodeFilter.all,
  }) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    String? whereClause;
    List<dynamic>? whereArgs;

    if (filter == EpisodeFilter.unplayed) {
      whereClause = '$_isPlayedCol = 0 AND (duration IS NULL OR duration = 0 OR position < (duration - 10))';
    } else if (filter == EpisodeFilter.finished) {
      whereClause = '($_isPlayedCol = 1 OR (duration IS NOT NULL AND duration > 0 AND position >= (duration - 10)))';
    }

    final maps = await db.query(
      'episodes',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '$_pubDateCol DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<List<Episode>> getAllUnplayedEpisodes() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final maps = await db.query(
      'episodes',
      where: '$_isPlayedCol = 0',
      orderBy: '$_pubDateCol DESC',
    );
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<Episode?> getEpisodeByMediaUrl(String mediaUrl) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final maps = await db.query(
      'episodes',
      where: '$_mediaUrlCol = ?',
      whereArgs: [mediaUrl],
    );
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
    return db.insert('gpodder_actions', action.toMap());
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
