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
  String _isStarredCol = 'isStarred';
  String _mediaUrlCol = 'mediaUrl';
  String _podcastRssUrlCol = 'rssUrl';
  bool _columnsDetected = false;
  Completer<void>? _detectCompleter;

  Future<void> _detectColumnNames(Database db) async {
    if (_columnsDetected) return;
    if (_detectCompleter != null) return _detectCompleter!.future;
    _detectCompleter = Completer<void>();
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

      if (epCols.contains('isStarred')) {
        _isStarredCol = 'isStarred';
      } else if (epCols.contains('is_starred')) {
        _isStarredCol = 'is_starred';
      }

      if (!epCols.contains('isStarred') && !epCols.contains('is_starred')) {
        try {
          await db.execute('ALTER TABLE episodes ADD COLUMN isStarred INTEGER NOT NULL DEFAULT 0;');
        } catch (_) {}
      }

      if (epCols.contains('mediaUrl')) {
        _mediaUrlCol = 'mediaUrl';
      } else if (epCols.contains('media_url')) {
        _mediaUrlCol = 'media_url';
      }

      if (!epCols.contains('downloadPath')) {
        try {
          await db.execute('ALTER TABLE episodes ADD COLUMN downloadPath TEXT;');
        } catch (_) {}
      }
      if (!epCols.contains('downloadStatus')) {
        try {
          await db.execute("ALTER TABLE episodes ADD COLUMN downloadStatus TEXT NOT NULL DEFAULT 'none';");
        } catch (_) {}
      }
      if (!epCols.contains('downloadProgress')) {
        try {
          await db.execute('ALTER TABLE episodes ADD COLUMN downloadProgress REAL NOT NULL DEFAULT 0.0;');
        } catch (_) {}
      }
      if (!epCols.contains('downloadedBytes')) {
        try {
          await db.execute('ALTER TABLE episodes ADD COLUMN downloadedBytes INTEGER NOT NULL DEFAULT 0;');
        } catch (_) {}
      }
      if (!epCols.contains('totalBytes')) {
        try {
          await db.execute('ALTER TABLE episodes ADD COLUMN totalBytes INTEGER NOT NULL DEFAULT 0;');
        } catch (_) {}
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

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS subscription_backlog (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action TEXT NOT NULL,
            rssUrl TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');
      } catch (_) {}

      try {
        final gpodderActionInfo = await db.rawQuery('PRAGMA table_info(gpodder_actions)');
        final gpodderCols = gpodderActionInfo.map((row) => row['name'].toString()).toSet();
        if (!gpodderCols.contains('guid')) {
          await db.execute('ALTER TABLE gpodder_actions ADD COLUMN guid TEXT;');
        }
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS playback_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            episodeId INTEGER NOT NULL,
            sortOrder INTEGER NOT NULL,
            addedAt TEXT NOT NULL,
            FOREIGN KEY (episodeId) REFERENCES episodes (id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}

      _columnsDetected = true;
      _detectCompleter!.complete();
    } catch (e, stack) {
      _detectCompleter!.completeError(e, stack);
      _detectCompleter = null;
    }
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
        isStarred INTEGER NOT NULL DEFAULT 0,
        imageUrl TEXT,
        downloadPath TEXT,
        downloadStatus TEXT NOT NULL DEFAULT 'none',
        downloadProgress REAL NOT NULL DEFAULT 0.0,
        downloadedBytes INTEGER NOT NULL DEFAULT 0,
        totalBytes INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (podcastId) REFERENCES podcasts (id) ON DELETE CASCADE,
        UNIQUE (podcastId, guid)
      )
    ''');

    await db.execute('''
      CREATE TABLE gpodder_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        podcast TEXT,
        episode TEXT,
        guid TEXT,
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS subscription_backlog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        rssUrl TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS playback_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        episodeId INTEGER NOT NULL,
        sortOrder INTEGER NOT NULL,
        addedAt TEXT NOT NULL,
        FOREIGN KEY (episodeId) REFERENCES episodes (id) ON DELETE CASCADE
      )
    ''');
  }

  // PODCAST CRUD OPERATIONS

  Future<int> insertPodcast(Podcast podcast) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final existing = await getPodcastByUrl(podcast.rssUrl);
    if (existing != null) {
      final map = podcast.toMap();
      final id = podcast.id ?? existing.id;
      if (id != null) {
        map['id'] = id;
      }
      await db.update(
        'podcasts',
        map,
        where: '$_podcastRssUrlCol = ?',
        whereArgs: [podcast.rssUrl],
      );
      return id ?? existing.id ?? 0;
    } else {
      return db.insert(
        'podcasts',
        podcast.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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
    if (episodes.isEmpty) return;
    final db = await instance.database;
    await _detectColumnNames(db);

    final podcastIds = episodes.map((e) => e.podcastId).whereType<int>().toSet();
    final Map<String, Episode> existingByGuid = {};
    final Map<String, Episode> existingByMediaUrl = {};

    for (final podId in podcastIds) {
      final existingList = await getEpisodesForPodcast(podId);
      for (final existing in existingList) {
        if (existing.guid.isNotEmpty) {
          existingByGuid['$podId:${existing.guid}'] = existing;
        }
        if (existing.mediaUrl.isNotEmpty) {
          existingByMediaUrl['$podId:${existing.mediaUrl}'] = existing;
        }
      }
    }

    final batch = db.batch();
    for (final episode in episodes) {
      final podId = episode.podcastId;
      final guidKey = podId != null && episode.guid.isNotEmpty ? '$podId:${episode.guid}' : null;
      final mediaKey = podId != null && episode.mediaUrl.isNotEmpty ? '$podId:${episode.mediaUrl}' : null;

      final existing = (guidKey != null ? existingByGuid[guidKey] : null) ??
          (mediaKey != null ? existingByMediaUrl[mediaKey] : null);

      if (existing != null) {
        final finalPosition = existing.position > episode.position ? existing.position : episode.position;
        final finalIsPlayed = existing.isPlayed || episode.isPlayed;
        final finalIsStarred = existing.isStarred || episode.isStarred;

        final finalDownloadPath = episode.downloadPath ?? existing.downloadPath;
        final finalDownloadStatus = episode.downloadStatus != DownloadStatus.none
            ? episode.downloadStatus
            : existing.downloadStatus;
        final finalDownloadProgress = episode.downloadProgress > 0.0
            ? episode.downloadProgress
            : existing.downloadProgress;
        final finalDownloadedBytes = episode.downloadedBytes > 0
            ? episode.downloadedBytes
            : existing.downloadedBytes;
        final finalTotalBytes = episode.totalBytes > 0
            ? episode.totalBytes
            : existing.totalBytes;

        final adaptedMap = <String, dynamic>{
          _podcastIdCol: episode.podcastId,
          'guid': episode.guid,
          'title': episode.title,
          'description': episode.description,
          _mediaUrlCol: episode.mediaUrl,
          _pubDateCol: episode.publishedAt?.toIso8601String(),
          'duration': episode.duration > 0 ? episode.duration : existing.duration,
          'position': finalPosition,
          _isPlayedCol: finalIsPlayed ? 1 : 0,
          _isStarredCol: finalIsStarred ? 1 : 0,
          'imageUrl': episode.imageUrl.isNotEmpty ? episode.imageUrl : existing.imageUrl,
          'downloadPath': finalDownloadPath,
          'downloadStatus': finalDownloadStatus.name,
          'downloadProgress': finalDownloadProgress,
          'downloadedBytes': finalDownloadedBytes,
          'totalBytes': finalTotalBytes,
        };

        batch.update(
          'episodes',
          adaptedMap,
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      } else {
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
          _isStarredCol: episode.isStarred ? 1 : 0,
          'imageUrl': episode.imageUrl,
          'downloadPath': episode.downloadPath,
          'downloadStatus': episode.downloadStatus.name,
          'downloadProgress': episode.downloadProgress,
          'downloadedBytes': episode.downloadedBytes,
          'totalBytes': episode.totalBytes,
        };
        batch.insert(
          'episodes',
          adaptedMap,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
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
      whereClause += ' AND e.$_isPlayedCol = 0 AND (e.duration IS NULL OR e.duration = 0 OR e.position = 0 OR ((e.duration > 60 AND (e.duration - e.position) > 60) OR (e.duration <= 60 AND e.position < (CASE WHEN e.duration > 10 THEN e.duration - 10 ELSE e.duration END))))';
    } else if (filter == EpisodeFilter.finished) {
      whereClause += ' AND (e.$_isPlayedCol = 1 OR (e.duration IS NOT NULL AND e.duration > 0 AND e.position > 0 AND ((e.duration > 60 AND (e.duration - e.position) <= 60) OR (e.duration <= 60 AND e.position >= (CASE WHEN e.duration > 10 THEN e.duration - 10 ELSE e.duration END)))))';
    } else if (filter == EpisodeFilter.inProgress) {
      whereClause += ' AND e.$_isPlayedCol = 0 AND e.position > 0 AND ((e.duration IS NULL OR e.duration = 0) OR ((e.duration > 60 AND (e.duration - e.position) > 60) OR (e.duration <= 60 AND e.position < (CASE WHEN e.duration > 10 THEN e.duration - 10 ELSE e.duration END))))';
    } else if (filter == EpisodeFilter.starred) {
      whereClause += ' AND e.$_isStarredCol = 1';
    } else if (filter == EpisodeFilter.downloaded) {
      whereClause += " AND e.downloadStatus = 'downloaded' AND e.downloadPath IS NOT NULL";
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
      whereClause = 'e.$_isPlayedCol = 0 AND (e.duration IS NULL OR e.duration = 0 OR e.position = 0 OR ((e.duration > 60 AND (e.duration - e.position) > 60) OR (e.duration <= 60 AND e.position < (CASE WHEN e.duration > 10 THEN e.duration - 10 ELSE e.duration END))))';
    } else if (filter == EpisodeFilter.finished) {
      whereClause = '(e.$_isPlayedCol = 1 OR (e.duration IS NOT NULL AND e.duration > 0 AND e.position > 0 AND ((e.duration > 60 AND (e.duration - e.position) <= 60) OR (e.duration <= 60 AND e.position >= (CASE WHEN e.duration > 10 THEN e.duration - 10 ELSE e.duration END)))))';
    } else if (filter == EpisodeFilter.inProgress) {
      whereClause = 'e.$_isPlayedCol = 0 AND e.position > 0 AND ((e.duration IS NULL OR e.duration = 0) OR ((e.duration > 60 AND (e.duration - e.position) > 60) OR (e.duration <= 60 AND e.position < (CASE WHEN e.duration > 10 THEN e.duration - 10 ELSE e.duration END))))';
    } else if (filter == EpisodeFilter.starred) {
      whereClause = 'e.$_isStarredCol = 1';
    } else if (filter == EpisodeFilter.downloaded) {
      whereClause = "e.downloadStatus = 'downloaded' AND e.downloadPath IS NOT NULL";
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

  Future<int> updateEpisodeDownloadState(
    int episodeId, {
    required DownloadStatus status,
    String? downloadPath,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
  }) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final values = <String, dynamic>{
      'downloadStatus': status.name,
      'downloadPath': ?downloadPath,
      'downloadProgress': ?progress,
      'downloadedBytes': ?downloadedBytes,
      'totalBytes': ?totalBytes,
    };
    return db.update(
      'episodes',
      values,
      where: 'id = ?',
      whereArgs: [episodeId],
    );
  }

  Future<int> clearEpisodeDownload(int episodeId) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.update(
      'episodes',
      {
        'downloadStatus': DownloadStatus.none.name,
        'downloadPath': null,
        'downloadProgress': 0.0,
        'downloadedBytes': 0,
        'totalBytes': 0,
      },
      where: 'id = ?',
      whereArgs: [episodeId],
    );
  }

  Future<List<Episode>> getDownloadedEpisodes() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
      WHERE (LOWER(e.downloadStatus) = 'downloaded' OR (e.downloadPath IS NOT NULL AND e.downloadPath != ''))
      ORDER BY e.$_pubDateCol DESC
    ''';
    final maps = await db.rawQuery(query);
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<int> getTotalDownloadSizeBytes() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final res = await db.rawQuery(
      "SELECT SUM(downloadedBytes) as total FROM episodes WHERE LOWER(downloadStatus) = 'downloaded' OR (downloadPath IS NOT NULL AND downloadPath != '')",
    );
    if (res.isNotEmpty && res.first['total'] != null) {
      final total = res.first['total'];
      if (total is num) return total.toInt();
      if (total is String) return int.tryParse(total) ?? 0;
    }
    return 0;
  }

  Future<int> clearAllDownloadedEpisodes() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.update(
      'episodes',
      {
        'downloadStatus': DownloadStatus.none.name,
        'downloadPath': null,
        'downloadProgress': 0.0,
        'downloadedBytes': 0,
        'totalBytes': 0,
      },
      where: "downloadStatus = 'downloaded' OR downloadPath IS NOT NULL",
    );
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

  Future<int> setEpisodeStarred(int episodeId, bool isStarred) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.update(
      'episodes',
      {_isStarredCol: isStarred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [episodeId],
    );
  }

  Future<bool> toggleEpisodeStarred(int episodeId) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final rows = await db.query(
      'episodes',
      columns: [_isStarredCol],
      where: 'id = ?',
      whereArgs: [episodeId],
    );
    if (rows.isEmpty) return false;
    final currentVal = (rows.first[_isStarredCol] as num?)?.toInt() == 1;
    final newVal = !currentVal;
    await db.update(
      'episodes',
      {_isStarredCol: newVal ? 1 : 0},
      where: 'id = ?',
      whereArgs: [episodeId],
    );
    return newVal;
  }

  Future<List<Episode>> getStarredEpisodes({int limit = 100}) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      JOIN podcasts p ON e.$_podcastIdCol = p.id
      WHERE e.$_isStarredCol = 1
      ORDER BY e.$_pubDateCol DESC
      LIMIT $limit
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

  Future<Episode?> getEpisodeByGuid(String guid) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
      WHERE e.guid = ?
    ''';
    final maps = await db.rawQuery(query, [guid]);
    if (maps.isNotEmpty) {
      return Episode.fromMap(maps.first);
    }
    return null;
  }

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    try {
      u = Uri.decodeFull(u);
    } catch (_) {}
    if (u.startsWith('https://')) {
      u = u.substring(8);
    } else if (u.startsWith('http://')) {
      u = u.substring(7);
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final qIdx = u.indexOf('?');
    if (qIdx != -1) {
      u = u.substring(0, qIdx);
    }
    final fIdx = u.indexOf('#');
    if (fIdx != -1) {
      u = u.substring(0, fIdx);
    }
    return u.toLowerCase().trim();
  }

  /// Strips known podcast redirect trackers (Podtrac, Chartable, pdst.fm, etc.)
  /// to reveal the underlying media file URL.
  static String stripTrackingPrefixes(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    try {
      u = Uri.decodeFull(u);
    } catch (_) {}

    final lastHttpIdx = u.lastIndexOf('http://');
    final lastHttpsIdx = u.lastIndexOf('https://');
    final lastSchemeIdx = lastHttpIdx > lastHttpsIdx ? lastHttpIdx : lastHttpsIdx;
    if (lastSchemeIdx > 8) {
      u = u.substring(lastSchemeIdx);
    } else {
      final prefixes = [
        RegExp(r'^https?://[^/]*podtrac\.com/[^/]+(?:/[^/]+)?/'),
        RegExp(r'^https?://[^/]*chrt\.fm/track/[^/]+/'),
        RegExp(r'^https?://[^/]*chtbl\.com/track/[^/]+/'),
        RegExp(r'^https?://[^/]*pdst\.fm/e/'),
        RegExp(r'^https?://[^/]*mgln\.ai/e/[^/]+/'),
        RegExp(r'^https?://[^/]*feedpress\.it/link/[^/]+/[^/]+/'),
        RegExp(r'^https?://[^/]*megaphone\.fm/ad-insertion/[^/]+/'),
      ];
      for (final prefix in prefixes) {
        if (prefix.hasMatch(u)) {
          u = u.replaceFirst(prefix, '');
          if (!u.startsWith('http://') && !u.startsWith('https://')) {
            u = 'https://$u';
          }
          break;
        }
      }
    }
    return normalizeUrl(u);
  }

  /// Extracts the audio filename from an audio URL path (e.g. "episode102.mp3")
  static String extractAudioFilename(String url) {
    try {
      final clean = normalizeUrl(url);
      final lastSlash = clean.lastIndexOf('/');
      if (lastSlash != -1 && lastSlash < clean.length - 1) {
        final filename = clean.substring(lastSlash + 1);
        if (filename.length >= 4 &&
            (filename.endsWith('.mp3') ||
             filename.endsWith('.m4a') ||
             filename.endsWith('.aac') ||
             filename.endsWith('.ogg') ||
             filename.endsWith('.opus') ||
             filename.contains('.'))) {
          return filename;
        }
      }
    } catch (_) {}
    return '';
  }

  /// Checks if any episode in the database has non-zero playback progress or is played
  Future<bool> hasAnyPlaybackProgress() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM episodes WHERE position > 0 OR $_isPlayedCol = 1',
    )) ?? 0;
    return count > 0;
  }

  Future<int> updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final count = await db.update(
      'episodes',
      {
        'position': position,
        _isPlayedCol: isPlayed ? 1 : 0,
      },
      where: '$_mediaUrlCol = ?',
      whereArgs: [mediaUrl],
    );
    if (count > 0) return count;

    // Fallback: match by guid or normalized URL if exact mediaUrl didn't match
    final epByGuid = await db.query('episodes', where: 'guid = ?', whereArgs: [mediaUrl]);
    if (epByGuid.isNotEmpty) {
      return db.update(
        'episodes',
        {
          'position': position,
          _isPlayedCol: isPlayed ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [epByGuid.first['id']],
      );
    }

    final norm = normalizeUrl(mediaUrl);
    if (norm.isNotEmpty) {
      final all = await db.query('episodes', columns: ['id', _mediaUrlCol]);
      for (final row in all) {
        final rowUrl = (row[_mediaUrlCol] ?? '').toString();
        if (normalizeUrl(rowUrl) == norm) {
          return db.update(
            'episodes',
            {
              'position': position,
              _isPlayedCol: isPlayed ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    }
    return 0;
  }

  Future<int> updateEpisodePlaybackState(String mediaUrl, int position, {bool isPlayed = false}) async =>
      updateEpisodeProgress(mediaUrl, position, isPlayed);

  /// Apply a batch of remote episode actions to local episodes with intelligent
  /// matching (by GUID, exact URL, and normalized URL), chronological ordering,
  /// and robust played state detection using episode duration from SQLite.
  Future<int> applyRemoteEpisodeActions(List<GPodderAction> actions) async {
    if (actions.isEmpty) return 0;
    final db = await instance.database;
    await _detectColumnNames(db);

    final epMaps = await db.rawQuery('''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM episodes e
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
    ''');
    final episodes = epMaps.map((m) => Episode.fromMap(m)).toList();
    if (episodes.isEmpty) return 0;

    final episodesById = <int, Episode>{};
    final byPodcastAndGuid = <String, int>{};
    final byPodcastAndNormalizedGuid = <String, int>{};
    final byGuid = <String, int>{};
    final byGuidCaseInsensitive = <String, int>{};
    final byNormalizedGuid = <String, int>{};
    final byStrippedGuid = <String, int>{};

    final byPodcastAndMediaUrl = <String, int>{};
    final byPodcastAndNormalizedMediaUrl = <String, int>{};
    final byPodcastAndStrippedMediaUrl = <String, int>{};
    final byMediaUrl = <String, int>{};
    final byNormalizedMediaUrl = <String, int>{};
    final byStrippedMediaUrl = <String, int>{};

    final byPodcastAndFilename = <String, int>{};
    final filenameCount = <String, int>{};
    final byFilename = <String, int>{};

    for (final ep in episodes) {
      final epId = ep.id;
      if (epId == null) continue;
      episodesById[epId] = ep;

      final normPod = normalizeUrl(ep.podcastRss);
      final guid = ep.guid.trim();
      final normGuid = normalizeUrl(guid);
      final strippedGuid = stripTrackingPrefixes(guid);
      final mediaUrl = ep.mediaUrl.trim();
      final normMediaUrl = normalizeUrl(mediaUrl);
      final strippedMediaUrl = stripTrackingPrefixes(mediaUrl);
      final filename = extractAudioFilename(mediaUrl);

      if (guid.isNotEmpty) {
        if (normPod.isNotEmpty) {
          byPodcastAndGuid['$normPod|$guid'] = epId;
          if (normGuid.isNotEmpty) {
            byPodcastAndNormalizedGuid['$normPod|$normGuid'] = epId;
          }
        }
        byGuid.putIfAbsent(guid, () => epId);
        byGuidCaseInsensitive.putIfAbsent(guid.toLowerCase(), () => epId);
        if (normGuid.isNotEmpty) {
          byNormalizedGuid.putIfAbsent(normGuid, () => epId);
        }
        if (strippedGuid.isNotEmpty) {
          byStrippedGuid.putIfAbsent(strippedGuid, () => epId);
        }
      }

      if (mediaUrl.isNotEmpty) {
        if (normPod.isNotEmpty) {
          byPodcastAndMediaUrl['$normPod|$mediaUrl'] = epId;
          if (normMediaUrl.isNotEmpty) {
            byPodcastAndNormalizedMediaUrl['$normPod|$normMediaUrl'] = epId;
          }
          if (strippedMediaUrl.isNotEmpty) {
            byPodcastAndStrippedMediaUrl['$normPod|$strippedMediaUrl'] = epId;
          }
        }
        byMediaUrl.putIfAbsent(mediaUrl, () => epId);
        if (normMediaUrl.isNotEmpty) {
          byNormalizedMediaUrl.putIfAbsent(normMediaUrl, () => epId);
        }
        if (strippedMediaUrl.isNotEmpty) {
          byStrippedMediaUrl.putIfAbsent(strippedMediaUrl, () => epId);
        }
      }

      if (filename.isNotEmpty) {
        if (normPod.isNotEmpty) {
          byPodcastAndFilename['$normPod|$filename'] = epId;
        }
        filenameCount[filename] = (filenameCount[filename] ?? 0) + 1;
        if (filenameCount[filename] == 1) {
          byFilename[filename] = epId;
        } else {
          byFilename.remove(filename); // Not unique
        }
      }
    }

    final actionsByEpisodeId = <int, List<GPodderAction>>{};

    for (final action in actions) {
      final actName = action.action.toLowerCase().trim();
      final isPlayLike = actName == 'play' ||
          actName == 'played' ||
          actName == 'finish' ||
          actName == 'finished' ||
          actName == 'completed' ||
          actName == 'listen' ||
          actName == 'listened' ||
          actName == 'pause' ||
          actName == 'stop' ||
          actName == 'progress' ||
          action.position > 0;
      final isNewLike = actName == 'new';
      if (!isPlayLike && !isNewLike) continue;

      final guid = action.guid?.trim();
      final normGuid = guid != null ? normalizeUrl(guid) : '';
      final strippedActionGuid = guid != null ? stripTrackingPrefixes(guid) : '';
      final epUrl = action.episode.trim();
      final podUrl = action.podcast.trim();
      final normPod = normalizeUrl(podUrl);
      final normEp = normalizeUrl(epUrl);
      final strippedEp = stripTrackingPrefixes(epUrl);
      final actFilename = extractAudioFilename(epUrl);

      int? matchedId;

      // 1. Try matching by action.guid within podcast
      if (guid != null && guid.isNotEmpty && guid.toLowerCase() != 'null') {
        if (normPod.isNotEmpty) {
          matchedId = byPodcastAndGuid['$normPod|$guid'];
          if (matchedId == null && normGuid.isNotEmpty) {
            matchedId = byPodcastAndNormalizedGuid['$normPod|$normGuid'];
          }
        }
        // 2. Try matching by action.guid globally
        matchedId ??= byGuid[guid];
        matchedId ??= byGuidCaseInsensitive[guid.toLowerCase()];
        if (matchedId == null && normGuid.isNotEmpty) {
          matchedId = byNormalizedGuid[normGuid];
        }
        if (matchedId == null && strippedActionGuid.isNotEmpty) {
          matchedId = byStrippedGuid[strippedActionGuid];
        }
      }

      // 3. Try stripped mediaUrl within podcast
      if (matchedId == null && strippedEp.isNotEmpty && normPod.isNotEmpty) {
        matchedId = byPodcastAndStrippedMediaUrl['$normPod|$strippedEp'];
      }

      // 4. Try normalized mediaUrl within podcast
      if (matchedId == null && normEp.isNotEmpty && normPod.isNotEmpty) {
        matchedId = byPodcastAndNormalizedMediaUrl['$normPod|$normEp'];
      }

      // 5. Try exact mediaUrl within podcast
      if (matchedId == null && epUrl.isNotEmpty && normPod.isNotEmpty) {
        matchedId = byPodcastAndMediaUrl['$normPod|$epUrl'];
      }

      // 6. Try audio filename within podcast
      if (matchedId == null && actFilename.isNotEmpty && normPod.isNotEmpty) {
        matchedId = byPodcastAndFilename['$normPod|$actFilename'];
      }

      // 7. Try stripped mediaUrl globally
      if (matchedId == null && strippedEp.isNotEmpty) {
        matchedId = byStrippedMediaUrl[strippedEp];
      }

      // 8. Try normalized mediaUrl globally
      if (matchedId == null && normEp.isNotEmpty) {
        matchedId = byNormalizedMediaUrl[normEp];
      }

      // 9. Try exact mediaUrl globally
      if (matchedId == null && epUrl.isNotEmpty) {
        matchedId = byMediaUrl[epUrl];
      }

      // 10. Try unique audio filename globally
      if (matchedId == null && actFilename.isNotEmpty && actFilename.length >= 10) {
        matchedId = byFilename[actFilename];
      }

      // 11. Cross-matching: test action.episode against guid
      if (matchedId == null && epUrl.isNotEmpty) {
        if (normPod.isNotEmpty) {
          matchedId = byPodcastAndGuid['$normPod|$epUrl'];
          if (matchedId == null && normEp.isNotEmpty) {
            matchedId = byPodcastAndNormalizedGuid['$normPod|$normEp'];
          }
        }
        matchedId ??= byGuid[epUrl];
        if (matchedId == null && normEp.isNotEmpty) {
          matchedId = byNormalizedGuid[normEp];
        }
      }

      // 12. Cross-matching: test action.guid against mediaUrl
      if (matchedId == null && guid != null && guid.isNotEmpty && guid.toLowerCase() != 'null') {
        matchedId = byStrippedMediaUrl[stripTrackingPrefixes(guid)];
        matchedId ??= byNormalizedMediaUrl[normalizeUrl(guid)];
        matchedId ??= byMediaUrl[guid];
      }

      // 13. Suffix match within podcast (handles complex redirect/CDN wrappers)
      if (matchedId == null && normPod.isNotEmpty && normEp.isNotEmpty) {
        for (final ep in episodes) {
          if (normalizeUrl(ep.podcastRss) == normPod) {
            final epNorm = normalizeUrl(ep.mediaUrl);
            if (epNorm.length >= 15 && normEp.length >= 15) {
              if (epNorm.endsWith(normEp) || normEp.endsWith(epNorm)) {
                matchedId = ep.id;
                break;
              }
            }
          }
        }
      }

      if (matchedId != null) {
        actionsByEpisodeId.putIfAbsent(matchedId, () => []).add(action);
      }
    }

    final batch = db.batch();
    int updateCount = 0;

    for (final entry in actionsByEpisodeId.entries) {
      final epId = entry.key;
      final ep = episodesById[epId]!;
      final epActions = entry.value;

      // Sort chronologically: oldest first, latest last
      epActions.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      int finalPos = ep.position;
      bool finalPlayed = ep.isPlayed;
      final epDuration = ep.duration;

      for (final act in epActions) {
        final actType = act.action.toLowerCase().trim();
        if (actType == 'new') {
          finalPos = 0;
          finalPlayed = false;
          continue;
        }

        final actPos = act.position < 0 ? 0 : act.position;
        final total = act.total > 0 ? act.total : epDuration;

        bool isActPlayed = false;
        if (actType == 'played' ||
            actType == 'finish' ||
            actType == 'finished' ||
            actType == 'completed') {
          isActPlayed = true;
        } else if (total > 0 && actPos > 0 && (total > 60 ? (total - actPos) <= 60 : actPos >= (total > 10 ? total - 10 : total))) {
          isActPlayed = true;
        } else if (total > 0 && actPos >= (total * 0.95).round()) {
          isActPlayed = true;
        } else if (act.started > 0 && act.started == actPos && epDuration > 0 && actPos >= (epDuration > 60 ? epDuration - 60 : epDuration - 15)) {
          isActPlayed = true;
        } else if (act.started > 0 && actPos > 0 && act.started == actPos && (total <= 0 || actPos >= total)) {
          // AntennaPod mark as played often sets started == position == duration
          isActPlayed = true;
        }

        if (isActPlayed) {
          finalPlayed = true;
          finalPos = actPos > finalPos ? actPos : (finalPos > 0 ? finalPos : (epDuration > 0 ? epDuration : actPos));
          if (finalPos == 0 && epDuration > 0) {
            finalPos = epDuration;
          }
        } else {
          finalPos = actPos;
          if (finalPlayed && actPos < 30) {
            // Retain played state if previously finished and this is just an accidental scrub
          } else {
            finalPlayed = false;
          }
        }
      }

      if (epDuration > 0 && finalPos > epDuration) {
        finalPos = epDuration;
      }

      if (finalPos != ep.position || (finalPlayed ? 1 : 0) != (ep.isPlayed ? 1 : 0)) {
        batch.update(
          'episodes',
          {
            'position': finalPos,
            _isPlayedCol: finalPlayed ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [epId],
        );
        updateCount++;
      }
    }

    if (updateCount > 0) {
      await batch.commit(noResult: true);
    }
    if (kDebugMode) {
      print('applyRemoteEpisodeActions: received ${actions.length} actions, matched ${actionsByEpisodeId.length} episodes, updated $updateCount episodes in SQLite');
    }
    return updateCount;
  }

  // GPODDER OFFLINE ACTION QUEUE & BACKLOG

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

    if (action.action == 'play') {
      final podcastCol = cols.contains('podcast') ? 'podcast' : 'podcastUrl';
      final episodeCol = cols.contains('episode') ? 'episode' : 'episodeUrl';

      String whereClause = '$podcastCol = ? AND $episodeCol = ? AND action = ?';
      List<dynamic> whereArgs = [action.podcast, action.episode, 'play'];

      if (cols.contains('guid') && action.guid != null && action.guid!.isNotEmpty) {
        whereClause = '$podcastCol = ? AND (guid = ? OR $episodeCol = ?) AND action = ?';
        whereArgs = [action.podcast, action.guid, action.episode, 'play'];
      }

      final existing = await db.query(
        'gpodder_actions',
        where: whereClause,
        whereArgs: whereArgs,
      );

      if (existing.isNotEmpty) {
        final existingId = (existing.first['id'] as num).toInt();
        await db.update(
          'gpodder_actions',
          adapted,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      }
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
        final epKey = (action.guid != null && action.guid!.isNotEmpty) ? action.guid! : action.episodeMediaUrl;
        final key = '${action.podcastFeedUrl}|$epKey';
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

  // SUBSCRIPTION OFFLINE BACKLOG & DEDUPLICATION

  /// Enqueue subscription change ('add' or 'remove') with smart cancel-out logic.
  /// If opposing action exists (e.g. 'add' followed by 'remove' or vice versa for same rssUrl),
  /// both actions cancel out to 0 pending network requests!
  Future<void> queueSubscriptionChange(String action, String rssUrl) async {
    final db = await instance.database;
    await _detectColumnNames(db);

    final pending = await db.query(
      'subscription_backlog',
      where: 'rssUrl = ?',
      whereArgs: [rssUrl],
    );

    if (pending.isNotEmpty) {
      final existingAction = pending.first['action'] as String;
      final existingId = (pending.first['id'] as num).toInt();

      if ((existingAction == 'add' && action == 'remove') ||
          (existingAction == 'remove' && action == 'add')) {
        // Opposing action: cancel out both! Delete existing entry and skip inserting new one.
        await db.delete(
          'subscription_backlog',
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return;
      } else if (existingAction == action) {
        // Duplicate action: update timestamp
        await db.update(
          'subscription_backlog',
          {'timestamp': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return;
      }
    }

    await db.insert('subscription_backlog', {
      'action': action,
      'rssUrl': rssUrl,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get deduplicated subscription changes to push to gPodder
  Future<Map<String, dynamic>> getPendingSubscriptionChanges() async {
    final db = await instance.database;
    await _detectColumnNames(db);

    final maps = await db.query('subscription_backlog', orderBy: 'id ASC');
    if (maps.isEmpty) {
      return {'add': <String>[], 'remove': <String>[], 'maxId': 0};
    }

    final addSet = <String>{};
    final removeSet = <String>{};
    int maxId = 0;

    for (final map in maps) {
      final id = (map['id'] as num).toInt();
      if (id > maxId) maxId = id;
      final action = map['action'] as String;
      final rssUrl = map['rssUrl'] as String;

      if (action == 'add') {
        removeSet.remove(rssUrl);
        addSet.add(rssUrl);
      } else if (action == 'remove') {
        addSet.remove(rssUrl);
        removeSet.add(rssUrl);
      }
    }

    return {
      'add': addSet.toList(),
      'remove': removeSet.toList(),
      'maxId': maxId,
    };
  }

  /// Clear subscription backlog items up to maxId
  Future<int> clearSubscriptionChangesUpTo(int maxId) async {
    final db = await instance.database;
    return db.delete(
      'subscription_backlog',
      where: 'id <= ?',
      whereArgs: [maxId],
    );
  }

  // PLAYBACK QUEUE CRUD OPERATIONS

  Future<int> addToQueue(Episode episode, {bool playNext = false}) async {
    final db = await instance.database;
    await _detectColumnNames(db);

    int? episodeId = episode.id;
    if (episodeId == null || episodeId <= 0) {
      Episode? existing;
      if (episode.guid.isNotEmpty) {
        existing = await getEpisodeByGuid(episode.guid);
      }
      if (existing == null && episode.mediaUrl.isNotEmpty) {
        existing = await getEpisodeByMediaUrl(episode.mediaUrl);
      }
      if (existing != null) {
        episodeId = existing.id;
      } else {
        var epToInsert = episode;
        if ((epToInsert.podcastId == null || epToInsert.podcastId! <= 0) && epToInsert.podcastRss.isNotEmpty) {
          final pod = await getPodcastByRssUrl(epToInsert.podcastRss);
          if (pod != null && pod.id != null) {
            epToInsert = epToInsert.copyWith(podcastId: pod.id);
          }
        }
        await insertEpisodes([epToInsert]);
        final inserted = await getEpisodeByMediaUrl(epToInsert.mediaUrl);
        episodeId = inserted?.id;
      }
    }

    if (episodeId == null) return 0;

    // Remove if already in queue to avoid duplicates
    await db.delete('playback_queue', where: 'episodeId = ?', whereArgs: [episodeId]);

    int sortOrder;
    if (playNext) {
      // Shift all existing items' sortOrder by +1
      await db.rawUpdate('UPDATE playback_queue SET sortOrder = sortOrder + 1');
      sortOrder = 0;
    } else {
      final maxResult = Sqflite.firstIntValue(
        await db.rawQuery('SELECT MAX(sortOrder) FROM playback_queue'),
      ) ?? -1;
      sortOrder = maxResult + 1;
    }

    return db.insert('playback_queue', {
      'episodeId': episodeId,
      'sortOrder': sortOrder,
      'addedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<int> removeFromQueue(int episodeId) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.delete(
      'playback_queue',
      where: 'episodeId = ?',
      whereArgs: [episodeId],
    );
  }

  Future<List<Episode>> getQueue() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final query = '''
      SELECT e.*, p.$_podcastRssUrlCol AS podcastRss
      FROM playback_queue q
      JOIN episodes e ON q.episodeId = e.id
      LEFT JOIN podcasts p ON e.$_podcastIdCol = p.id
      ORDER BY q.sortOrder ASC, q.id ASC
    ''';
    final maps = await db.rawQuery(query);
    return maps.map((map) => Episode.fromMap(map)).toList();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final db = await instance.database;
    await _detectColumnNames(db);
    final items = await db.query('playback_queue', orderBy: 'sortOrder ASC, id ASC');
    if (items.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= items.length) newIndex = items.length - 1;
    if (oldIndex == newIndex) return;

    final queueList = List<Map<String, dynamic>>.from(items);
    final moved = queueList.removeAt(oldIndex);
    queueList.insert(newIndex, moved);

    final batch = db.batch();
    for (int i = 0; i < queueList.length; i++) {
      batch.update(
        'playback_queue',
        {'sortOrder': i},
        where: 'id = ?',
        whereArgs: [queueList[i]['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> clearQueue() async {
    final db = await instance.database;
    await _detectColumnNames(db);
    return db.delete('playback_queue');
  }
}
