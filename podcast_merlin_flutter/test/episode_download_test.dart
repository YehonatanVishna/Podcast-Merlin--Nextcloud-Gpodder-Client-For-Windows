import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/episode_list_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/settings_view.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper db;

  setUpAll(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('merlin_download_tests_');
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');
  });

  group('Episode Model Download Fields & Serialization', () {
    test('Default values for download attributes', () {
      const ep = Episode(
        guid: 'test-guid-1',
        title: 'Episode 1',
        mediaUrl: 'https://example.com/ep1.mp3',
        description: 'Desc',
        imageUrl: 'https://example.com/img.png',
        podcastRss: 'https://example.com/feed.xml',
      );

      expect(ep.downloadPath, isNull);
      expect(ep.downloadStatus, DownloadStatus.none);
      expect(ep.downloadProgress, 0.0);
      expect(ep.downloadedBytes, 0);
      expect(ep.totalBytes, 0);
      expect(ep.isDownloaded, isFalse);
      expect(ep.isDownloading, isFalse);
    });

    test('isDownloaded is true only when downloaded and downloadPath != null', () {
      const epNotDownloaded = Episode(
        guid: 'test-guid-1',
        title: 'Episode 1',
        mediaUrl: 'https://example.com/ep1.mp3',
        description: 'Desc',
        imageUrl: '',
        podcastRss: '',
        downloadStatus: DownloadStatus.downloaded,
        downloadPath: null,
      );
      expect(epNotDownloaded.isDownloaded, isFalse);

      const epDownloaded = Episode(
        guid: 'test-guid-2',
        title: 'Episode 2',
        mediaUrl: 'https://example.com/ep2.mp3',
        description: 'Desc',
        imageUrl: '',
        podcastRss: '',
        downloadStatus: DownloadStatus.downloaded,
        downloadPath: '/path/to/ep2.mp3',
      );
      expect(epDownloaded.isDownloaded, isTrue);
    });

    test('isDownloading is true for downloading and queued statuses', () {
      const epQueued = Episode(
        guid: 'g1',
        title: 'E1',
        mediaUrl: 'url',
        description: '',
        imageUrl: '',
        podcastRss: '',
        downloadStatus: DownloadStatus.queued,
      );
      expect(epQueued.isDownloading, isTrue);

      const epDownloading = Episode(
        guid: 'g2',
        title: 'E2',
        mediaUrl: 'url',
        description: '',
        imageUrl: '',
        podcastRss: '',
        downloadStatus: DownloadStatus.downloading,
      );
      expect(epDownloading.isDownloading, isTrue);

      const epNone = Episode(
        guid: 'g3',
        title: 'E3',
        mediaUrl: 'url',
        description: '',
        imageUrl: '',
        podcastRss: '',
        downloadStatus: DownloadStatus.none,
      );
      expect(epNone.isDownloading, isFalse);
    });

    test('toMap and fromMap serialize and deserialize download attributes', () {
      const original = Episode(
        id: 42,
        podcastId: 10,
        guid: 'guid-42',
        title: 'Offline Episode',
        mediaUrl: 'https://example.com/offline.mp3',
        description: 'Notes',
        imageUrl: 'https://example.com/pic.png',
        podcastRss: 'https://example.com/feed.xml',
        downloadPath: '/data/downloads/offline.mp3',
        downloadStatus: DownloadStatus.downloaded,
        downloadProgress: 1.0,
        downloadedBytes: 15728640,
        totalBytes: 15728640,
      );

      final map = original.toMap();
      expect(map['downloadPath'], '/data/downloads/offline.mp3');
      expect(map['downloadStatus'], 'downloaded');
      expect(map['downloadProgress'], 1.0);
      expect(map['downloadedBytes'], 15728640);
      expect(map['totalBytes'], 15728640);

      final restored = Episode.fromMap(map);
      expect(restored.id, 42);
      expect(restored.guid, 'guid-42');
      expect(restored.downloadPath, '/data/downloads/offline.mp3');
      expect(restored.downloadStatus, DownloadStatus.downloaded);
      expect(restored.downloadProgress, 1.0);
      expect(restored.downloadedBytes, 15728640);
      expect(restored.totalBytes, 15728640);
      expect(restored.isDownloaded, isTrue);
    });

    test('copyWith updates download fields correctly', () {
      const ep = Episode(
        guid: 'g',
        title: 'Title',
        mediaUrl: 'url',
        description: '',
        imageUrl: '',
        podcastRss: '',
      );

      final updated = ep.copyWith(
        downloadPath: '/new/path.mp3',
        downloadStatus: DownloadStatus.downloading,
        downloadProgress: 0.5,
        downloadedBytes: 500,
        totalBytes: 1000,
      );

      expect(updated.downloadPath, '/new/path.mp3');
      expect(updated.downloadStatus, DownloadStatus.downloading);
      expect(updated.downloadProgress, 0.5);
      expect(updated.downloadedBytes, 500);
      expect(updated.totalBytes, 1000);
    });
  });

  group('DatabaseHelper Download Persistence & Queries', () {
    late int testPodId;

    setUp(() async {
      testPodId = await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: 'https://download-test.com/feed.xml',
          title: 'Download Test Podcast',
          description: 'Testing downloads',
          imageUrl: 'https://download-test.com/logo.png',
          link: 'https://download-test.com',
          lastUpdated: DateTime.now(),
        ),
      );
    });

    test('updateEpisodeDownloadState and clearEpisodeDownload', () async {
      await db.insertEpisodes([
        Episode(
          podcastId: testPodId,
          guid: 'ep-dl-1',
          title: 'Episode Download 1',
          mediaUrl: 'https://download-test.com/ep1.mp3',
          description: 'Desc',
          imageUrl: '',
          podcastRss: 'https://download-test.com/feed.xml',
        ),
      ]);

      final fetched = await db.getEpisodesForPodcast(testPodId);
      expect(fetched, hasLength(1));
      final epId = fetched.first.id!;

      // Update to downloading
      await db.updateEpisodeDownloadState(
        epId,
        status: DownloadStatus.downloading,
        progress: 0.35,
        downloadedBytes: 3500,
        totalBytes: 10000,
      );

      var check = (await db.getEpisodesForPodcast(testPodId)).first;
      expect(check.downloadStatus, DownloadStatus.downloading);
      expect(check.downloadProgress, closeTo(0.35, 0.001));
      expect(check.downloadedBytes, 3500);
      expect(check.totalBytes, 10000);

      // Update to downloaded
      await db.updateEpisodeDownloadState(
        epId,
        status: DownloadStatus.downloaded,
        downloadPath: '/data/ep1.mp3',
        progress: 1.0,
        downloadedBytes: 10000,
        totalBytes: 10000,
      );

      check = (await db.getEpisodesForPodcast(testPodId)).first;
      expect(check.downloadStatus, DownloadStatus.downloaded);
      expect(check.downloadPath, '/data/ep1.mp3');
      expect(check.isDownloaded, isTrue);

      // Clear download
      await db.clearEpisodeDownload(epId);
      check = (await db.getEpisodesForPodcast(testPodId)).first;
      expect(check.downloadStatus, DownloadStatus.none);
      expect(check.downloadPath, isNull);
      expect(check.downloadProgress, 0.0);
      expect(check.isDownloaded, isFalse);
    });

    test('getEpisodesForPodcast and getAllEpisodes filter by EpisodeFilter.downloaded', () async {
      await db.insertEpisodes([
        Episode(
          podcastId: testPodId,
          guid: 'ep-online',
          title: 'Online Ep',
          mediaUrl: 'https://download-test.com/online.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://download-test.com/feed.xml',
        ),
        Episode(
          podcastId: testPodId,
          guid: 'ep-offline',
          title: 'Offline Ep',
          mediaUrl: 'https://download-test.com/offline.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://download-test.com/feed.xml',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: '/data/offline.mp3',
          downloadProgress: 1.0,
          downloadedBytes: 8000,
          totalBytes: 8000,
        ),
      ]);

      // Filter: downloaded for podcast
      final downloadedInPod = await db.getEpisodesForPodcast(
        testPodId,
        filter: EpisodeFilter.downloaded,
      );
      expect(downloadedInPod, hasLength(1));
      expect(downloadedInPod.first.guid, 'ep-offline');

      // Filter: all for podcast
      final allInPod = await db.getEpisodesForPodcast(
        testPodId,
        filter: EpisodeFilter.all,
      );
      expect(allInPod, hasLength(2));

      // Filter: downloaded across all episodes
      final allDownloaded = await db.getAllEpisodes(
        filter: EpisodeFilter.downloaded,
      );
      expect(allDownloaded, hasLength(1));
      expect(allDownloaded.first.guid, 'ep-offline');
    });

    test('getTotalDownloadSizeBytes and clearAllDownloadedEpisodes', () async {
      await db.insertEpisodes([
        Episode(
          podcastId: testPodId,
          guid: 'ep-dl-1',
          title: 'DL 1',
          mediaUrl: 'https://download-test.com/1.mp3',
          description: '',
          imageUrl: '',
          podcastRss: '',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: '/data/1.mp3',
          downloadedBytes: 1000,
        ),
        Episode(
          podcastId: testPodId,
          guid: 'ep-dl-2',
          title: 'DL 2',
          mediaUrl: 'https://download-test.com/2.mp3',
          description: '',
          imageUrl: '',
          podcastRss: '',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: '/data/2.mp3',
          downloadedBytes: 2500,
        ),
      ]);

      final totalBytes = await db.getTotalDownloadSizeBytes();
      expect(totalBytes, 3500);

      final cleared = await db.clearAllDownloadedEpisodes();
      expect(cleared, 2);

      final totalAfter = await db.getTotalDownloadSizeBytes();
      expect(totalAfter, 0);

      final downloadedAfter = await db.getDownloadedEpisodes();
      expect(downloadedAfter, isEmpty);
    });

    test('insertEpisodes preserves existing download status on feed refresh', () async {
      await db.insertEpisodes([
        Episode(
          podcastId: testPodId,
          guid: 'ep-preserve-dl',
          title: 'Original Title',
          mediaUrl: 'https://download-test.com/preserve.mp3',
          description: 'Original Desc',
          imageUrl: '',
          podcastRss: '',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: '/data/preserve.mp3',
          downloadProgress: 1.0,
          downloadedBytes: 9999,
          totalBytes: 9999,
        ),
      ]);

      // Feed refreshes with new episode metadata
      await db.insertEpisodes([
        Episode(
          podcastId: testPodId,
          guid: 'ep-preserve-dl',
          title: 'Updated Title',
          mediaUrl: 'https://download-test.com/preserve.mp3',
          description: 'Updated Desc',
          imageUrl: '',
          podcastRss: '',
          // downloadStatus default is none
        ),
      ]);

      final check = (await db.getEpisodesForPodcast(testPodId)).first;
      expect(check.title, 'Updated Title');
      expect(check.downloadStatus, DownloadStatus.downloaded);
      expect(check.downloadPath, '/data/preserve.mp3');
      expect(check.downloadedBytes, 9999);
      expect(check.isDownloaded, isTrue);
    });
  });

  group('EpisodeDownloadService Operations', () {
    late HttpServer mockServer;
    late String serverUrl;
    late Directory downloadDir;
    late EpisodeDownloadService service;

    setUp(() async {
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverUrl = 'http://${mockServer.address.address}:${mockServer.port}';

      mockServer.listen((request) async {
        final path = request.uri.path;
        if (path.endsWith('.mp3')) {
          final dummyBytes = utf8.encode('DUMMY_MP3_AUDIO_CONTENT_HEADER_1234567890');
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.headers.contentLength = dummyBytes.length;
          request.response.statusCode = HttpStatus.ok;
          request.response.add(dummyBytes);
          await request.response.close();
        } else if (path.contains('slow')) {
          // Slow response for cancellation testing
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentLength = 1000;
          await Future.delayed(const Duration(milliseconds: 300));
          if (!request.response.connectionInfo!.remoteAddress.isLoopback) {}
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });

      downloadDir = Directory('${tempDir.path}/downloads_${DateTime.now().millisecondsSinceEpoch}');
      await downloadDir.create(recursive: true);

      service = EpisodeDownloadService(
        db: db,
        downloadDirResolver: () async => downloadDir,
      );
    });

    tearDown(() async {
      service.dispose();
      await mockServer.close(force: true);
    });

    test('startDownload completes successfully and saves file to disk', () async {
      final podId = await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: '$serverUrl/feed.xml',
          title: 'DL Test Pod',
          description: '',
          imageUrl: '',
          link: '',
          lastUpdated: DateTime.now(),
        ),
      );

      final ep = Episode(
        podcastId: podId,
        guid: 'ep-srv-1',
        title: 'Service Download Episode',
        mediaUrl: '$serverUrl/audio1.mp3',
        description: 'Test',
        imageUrl: '',
        podcastRss: '$serverUrl/feed.xml',
      );
      await db.insertEpisodes([ep]);
      final savedEp = (await db.getEpisodesForPodcast(podId)).first;

      final events = <DownloadTaskEvent>[];
      final sub = service.onDownloadEvent.listen(events.add);

      await service.startDownload(savedEp);

      // Wait for download to finish
      int attempts = 0;
      while (service.isEpisodeActive(savedEp.id!) && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      await Future.delayed(const Duration(milliseconds: 150));
      await sub.cancel();

      // Verify DB state
      final updatedEp = (await db.getEpisodesForPodcast(podId)).first;
      expect(updatedEp.downloadStatus, DownloadStatus.downloaded);
      expect(updatedEp.isDownloaded, isTrue);
      expect(updatedEp.downloadPath, isNotNull);
      expect(updatedEp.downloadedBytes, greaterThan(0));

      // Verify file exists on disk
      final file = File(updatedEp.downloadPath!);
      expect(await file.exists(), isTrue);
      expect(await file.length(), updatedEp.downloadedBytes);

      // Verify emitted events included downloaded
      expect(events.any((e) => e.status == DownloadStatus.downloaded), isTrue);
    });

    test('deleteDownload removes file from disk and clears database state', () async {
      final podId = await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: '$serverUrl/feed.xml',
          title: 'DL Delete Test',
          description: '',
          imageUrl: '',
          link: '',
          lastUpdated: DateTime.now(),
        ),
      );

      final ep = Episode(
        podcastId: podId,
        guid: 'ep-del-1',
        title: 'Delete Ep',
        mediaUrl: '$serverUrl/audio_del.mp3',
        description: '',
        imageUrl: '',
        podcastRss: '$serverUrl/feed.xml',
      );
      await db.insertEpisodes([ep]);
      final savedEp = (await db.getEpisodesForPodcast(podId)).first;

      await service.startDownload(savedEp);

      // Wait for download completion
      while (service.isEpisodeActive(savedEp.id!)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await Future.delayed(const Duration(milliseconds: 100));

      final downloadedEp = (await db.getEpisodesForPodcast(podId)).first;
      expect(downloadedEp.isDownloaded, isTrue);
      final filePath = downloadedEp.downloadPath!;
      expect(await File(filePath).exists(), isTrue);

      // Delete the download
      await service.deleteDownload(downloadedEp);

      // Verify file removed and DB reset
      expect(await File(filePath).exists(), isFalse);
      final clearedEp = (await db.getEpisodesForPodcast(podId)).first;
      expect(clearedEp.downloadStatus, DownloadStatus.none);
      expect(clearedEp.downloadPath, isNull);
      expect(clearedEp.isDownloaded, isFalse);
    });

    test('verifyDownloadedFiles cleans up DB state if file was deleted on disk', () async {
      final podId = await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: '$serverUrl/feed.xml',
          title: 'DL Verify Test',
          description: '',
          imageUrl: '',
          link: '',
          lastUpdated: DateTime.now(),
        ),
      );

      final dummyPath = '${downloadDir.path}/ghost_ep.mp3';
      final dummyFile = File(dummyPath);
      await dummyFile.writeAsString('audio');

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-ghost-1',
          title: 'Ghost Episode',
          mediaUrl: 'https://example.com/ghost.mp3',
          description: '',
          imageUrl: '',
          podcastRss: '',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: dummyPath,
          downloadedBytes: 5,
        ),
      ]);

      // Manually delete the file from disk (simulating external deletion)
      await dummyFile.delete();

      await service.verifyDownloadedFiles();

      final checked = (await db.getEpisodesForPodcast(podId)).first;
      expect(checked.downloadStatus, DownloadStatus.none);
      expect(checked.downloadPath, isNull);
    });

    test('clearAllDownloads clears all files on disk and resets DB states', () async {
      final file1 = File('${downloadDir.path}/ep_1_test.mp3');
      await file1.writeAsString('audio 1');
      final file2 = File('${downloadDir.path}/ep_2_test.mp3');
      await file2.writeAsString('audio 2');

      final podId = await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: 'https://example.com/feed.xml',
          title: 'Clear All Pod',
          description: '',
          imageUrl: '',
          link: '',
          lastUpdated: DateTime.now(),
        ),
      );

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'c1',
          title: 'C1',
          mediaUrl: 'https://example.com/1.mp3',
          description: '',
          imageUrl: '',
          podcastRss: '',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: file1.path,
          downloadedBytes: 7,
        ),
        Episode(
          podcastId: podId,
          guid: 'c2',
          title: 'C2',
          mediaUrl: 'https://example.com/2.mp3',
          description: '',
          imageUrl: '',
          podcastRss: '',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: file2.path,
          downloadedBytes: 7,
        ),
      ]);

      final clearedCount = await service.clearAllDownloads();
      expect(clearedCount, 2);
      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isFalse);

      final remaining = await db.getDownloadedEpisodes();
      expect(remaining, isEmpty);
    });

    test('getTotalDownloadStorageBytes computes disk file size and self-heals when downloadedBytes is 0', () async {
      final sampleAudio = File('${downloadDir.path}/zero_db_bytes.mp3');
      await sampleAudio.writeAsString('12345678901234567890'); // 20 bytes

      final podId = await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: 'https://example.com/feed_calc.xml',
          title: 'Calc Pod',
          description: '',
          imageUrl: '',
          link: '',
          lastUpdated: DateTime.now(),
        ),
      );

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-zero-bytes',
          title: 'Zero DB Bytes Ep',
          mediaUrl: 'https://example.com/ep_zero.mp3',
          description: '',
          imageUrl: '',
          podcastRss: '',
          downloadStatus: DownloadStatus.downloaded,
          downloadPath: sampleAudio.path,
          downloadedBytes: 0, // DB record has 0 bytes
          totalBytes: 0,
        ),
      ]);

      final totalBytes = await service.getTotalDownloadStorageBytes();
      expect(totalBytes, 20);

      // Verify DB was self-healed
      final epList = await db.getDownloadedEpisodes();
      expect(epList.first.downloadedBytes, 20);
    });
  });

  group('AudioPlayerService Offline Playback Resolution', () {
    test('playEpisode uses local file path when episode isDownloaded and file exists', () async {
      String? loadedUrlOrPath;
      final audioHandler = MerlinAudioHandler(
        db: db,
        urlLoader: (source) async {
          loadedUrlOrPath = source;
        },
      );
      addTearDown(audioHandler.dispose);

      final localAudioFile = File('${tempDir.path}/offline_sample.mp3');
      await localAudioFile.writeAsString('offline audio bytes');

      final downloadedEp = Episode(
        id: 101,
        guid: 'offline-ep-1',
        title: 'Offline Playing Episode',
        mediaUrl: 'https://remote.com/streaming.mp3',
        description: '',
        imageUrl: '',
        podcastRss: '',
        downloadStatus: DownloadStatus.downloaded,
        downloadPath: localAudioFile.path,
      );

      await audioHandler.playEpisode(downloadedEp);
      expect(loadedUrlOrPath, localAudioFile.path);

      // If file doesn't exist, fall back to remote URL
      final missingFileEp = Episode(
        id: 102,
        guid: 'offline-ep-2',
        title: 'Missing File Episode',
        mediaUrl: 'https://remote.com/streaming.mp3',
        description: '',
        imageUrl: '',
        podcastRss: '',
        downloadStatus: DownloadStatus.downloaded,
        downloadPath: '/non/existent/path.mp3',
      );

      await audioHandler.playEpisode(missingFileEp);
      expect(loadedUrlOrPath, 'https://remote.com/streaming.mp3');
    });
  });

  group('UI & Widget Integration Tests', () {
    testWidgets('EpisodeListView displays Downloaded filter and handles empty state', (tester) async {
      final pod = Podcast(
        id: 1,
        rssUrl: 'https://example.com/pod.xml',
        title: 'Widget Test Podcast',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );

      final audioHandler = MockAudioHandler(db: db);
      addTearDown(audioHandler.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodesNotifierProvider(1).overrideWith(
              (ref) => TestEpisodesNotifier([], filter: EpisodeFilter.downloaded),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EpisodeListView(podcast: pod),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify the 'Downloaded' filter chip is rendered
      expect(find.byKey(const ValueKey('filter_downloaded')), findsOneWidget);

      // Verify the empty state message for downloaded episodes
      expect(find.text('No downloaded episodes yet'), findsOneWidget);
      expect(find.text('Download episodes to listen to them offline.'), findsOneWidget);
    });

    testWidgets('SettingsView displays Downloads & Storage card and triggers Clear All', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testAudioFile = File('${tempDir.path}/settings_test_ep.mp3');
      testAudioFile.writeAsStringSync('audio');

      await tester.runAsync(() async {
        final podId = await db.insertOrUpdatePodcast(
          Podcast(
            rssUrl: 'https://example.com/settings_pod.xml',
            title: 'Settings Pod',
            description: '',
            imageUrl: '',
            link: '',
            lastUpdated: DateTime.now(),
          ),
        );

        await db.insertEpisodes([
          Episode(
            podcastId: podId,
            guid: 'settings-ep-1',
            title: 'Settings Ep',
            mediaUrl: 'https://example.com/ep.mp3',
            description: '',
            imageUrl: '',
            podcastRss: '',
            downloadStatus: DownloadStatus.downloaded,
            downloadPath: testAudioFile.path,
            downloadedBytes: 1048576, // 1 MB
          ),
        ]);
      });

      final audioHandler = MockAudioHandler(db: db);
      addTearDown(audioHandler.dispose);

      final fakeStorage = FakeSecureStorageService();
      final downloadService = EpisodeDownloadService(
        db: db,
        downloadDirResolver: () async => tempDir,
      );
      addTearDown(downloadService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            secureStorageProvider.overrideWithValue(fakeStorage),
            audioHandlerProvider.overrideWithValue(audioHandler),
            episodeDownloadServiceProvider.overrideWithValue(downloadService),
            downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(1048576)),
            downloadedEpisodesCountProvider.overrideWith((ref) => Future.value(1)),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify "Downloads & Storage" section title exists
      expect(find.text('Downloads & Storage'), findsOneWidget);
      expect(find.text('Offline Storage Used'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);

      // Tap "Clear All" button
      await tester.tap(find.text('Clear All'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Confirmation dialog is shown
      expect(find.text('Clear All Downloads?'), findsOneWidget);
      expect(find.text('Delete All'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.text('Delete All'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      // Verify file is deleted
      expect(testAudioFile.existsSync(), isFalse);
    });
  });
}

class MockAudioHandler extends MerlinAudioHandler {
  Episode? _testCurrentEpisode;

  MockAudioHandler({DatabaseHelper? db}) : super(db: db ?? DatabaseHelper.instance, urlLoader: (_) async {});

  @override
  Episode? get currentEpisode => _testCurrentEpisode;

  @override
  Future<void> playEpisode(Episode episode) async {
    _testCurrentEpisode = episode;
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

class TestEpisodesNotifier extends StateNotifier<EpisodesState> implements EpisodesNotifier {
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
  Future<bool> toggleStar(Episode episode) async => false;

  @override
  void updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) {}
}
