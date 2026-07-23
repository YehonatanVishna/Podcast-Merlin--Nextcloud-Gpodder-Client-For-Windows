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

  Future<Database> _initDB(String filePath) async {
    // 1. Initialize FFI setup first on desktop/mobile
    setupFfi();

    if (kIsWeb) {
      return openDatabase(
        filePath,
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: _createDB,
      );
    }

    final dbPath = await getDatabasePath(filePath);

    return openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: _createDB,
    );
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
    final maps = await db.query(
      'podcasts',
      where: 'rssUrl = ?',
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
    return db.delete(
      'podcasts',
      where: 'rssUrl = ?',
      whereArgs: [rssUrl],
    );
  }

  // EPISODE CRUD OPERATIONS

  Future<void> insertEpisodes(List<Episode> episodes) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final episode in episodes) {
      batch.insert(
        'episodes',
        episode.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveEpisodesBatch(List<Episode> episodes) async => insertEpisodes(episodes);

  Future<List<Episode>> getEpisodesForPodcast(int podcastId) async {
    final db = await instance.database;
    final maps = await db.query(
      'episodes',
      where: 'podcastId = ?',
      whereArgs: [podcastId],
      orderBy: 'pubDate DESC',
    );
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<List<Episode>> getAllEpisodes() async {
    final db = await instance.database;
    final maps = await db.query('episodes', orderBy: 'pubDate DESC');
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<List<Episode>> getAllUnplayedEpisodes() async {
    final db = await instance.database;
    final maps = await db.query(
      'episodes',
      where: 'isPlayed = 0',
      orderBy: 'pubDate DESC',
    );
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<Episode?> getEpisodeByMediaUrl(String mediaUrl) async {
    final db = await instance.database;
    final maps = await db.query(
      'episodes',
      where: 'mediaUrl = ?',
      whereArgs: [mediaUrl],
    );
    if (maps.isNotEmpty) {
      return Episode.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) async {
    final db = await instance.database;
    return db.update(
      'episodes',
      {
        'position': position,
        'isPlayed': isPlayed ? 1 : 0,
      },
      where: 'mediaUrl = ?',
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
