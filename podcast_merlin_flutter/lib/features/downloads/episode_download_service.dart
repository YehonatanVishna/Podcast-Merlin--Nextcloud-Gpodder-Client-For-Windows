import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/episode.dart';

class DownloadTaskEvent {
  final int episodeId;
  final String mediaUrl;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String? downloadPath;
  final String? error;

  const DownloadTaskEvent({
    required this.episodeId,
    required this.mediaUrl,
    required this.status,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadPath,
    this.error,
  });

  @override
  String toString() =>
      'DownloadTaskEvent(ep: $episodeId, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
}

class EpisodeDownloadService {
  final DatabaseHelper _db;
  final Dio _dio;
  final int maxConcurrentDownloads;
  final Future<Directory> Function()? _customDirResolver;

  final Map<int, CancelToken> _activeDownloads = {};
  final List<Episode> _queuedEpisodes = [];
  final Map<int, DateTime> _lastProgressUpdate = {};

  final StreamController<DownloadTaskEvent> _eventController =
      StreamController<DownloadTaskEvent>.broadcast();

  Stream<DownloadTaskEvent> get onDownloadEvent => _eventController.stream;

  EpisodeDownloadService({
    DatabaseHelper? db,
    Dio? dio,
    this.maxConcurrentDownloads = 2,
    Future<Directory> Function()? downloadDirResolver,
  })  : _db = db ?? DatabaseHelper.instance,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 10),
              ),
            ),
        _customDirResolver = downloadDirResolver;

  void dispose() {
    for (final token in _activeDownloads.values) {
      token.cancel('Service disposed');
    }
    _activeDownloads.clear();
    _queuedEpisodes.clear();
    _eventController.close();
    _dio.close(force: true);
  }

  bool isEpisodeActive(int episodeId) => _activeDownloads.containsKey(episodeId);

  bool isEpisodeQueued(int episodeId) =>
      _queuedEpisodes.any((e) => e.id == episodeId);

  DownloadStatus getEpisodeStatus(Episode episode) {
    final epId = episode.id;
    if (epId != null) {
      if (isEpisodeActive(epId)) return DownloadStatus.downloading;
      if (isEpisodeQueued(epId)) return DownloadStatus.queued;
    }
    return episode.downloadStatus;
  }

  Future<Directory> getDownloadsDirectory() async {
    if (_customDirResolver != null) {
      final dir = await _customDirResolver();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }

    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(appSupportDir.path, 'downloads'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(p.join(tempDir.path, 'downloads'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
  }

  String _sanitizeFileName(String mediaUrl, int episodeId) {
    final bytes = md5.convert(mediaUrl.codeUnits).toString();
    final cleanUrl = mediaUrl.split('?').first.split('#').first.toLowerCase();
    String ext = '.mp3';
    if (cleanUrl.endsWith('.m4a')) {
      ext = '.m4a';
    } else if (cleanUrl.endsWith('.aac')) {
      ext = '.aac';
    } else if (cleanUrl.endsWith('.ogg') || cleanUrl.endsWith('.oga')) {
      ext = '.ogg';
    } else if (cleanUrl.endsWith('.wav')) {
      ext = '.wav';
    } else if (cleanUrl.endsWith('.mp4')) {
      ext = '.mp4';
    }
    return 'ep_${episodeId}_$bytes$ext';
  }

  Future<void> startDownload(Episode episode) async {
    int? epId = episode.id;
    if (epId == null) {
      final found = await _db.getEpisodeByGuid(episode.guid);
      epId = found?.id;
    }
    if (epId == null) return;

    final updatedEpisode = episode.copyWith(id: epId);

    // If already downloaded and file exists, do nothing
    if (updatedEpisode.isDownloaded && updatedEpisode.downloadPath != null) {
      final file = File(updatedEpisode.downloadPath!);
      if (await file.exists() && await file.length() > 0) {
        return;
      }
    }

    // If already downloading or queued, do nothing
    if (isEpisodeActive(epId) || isEpisodeQueued(epId)) {
      return;
    }

    if (_activeDownloads.length < maxConcurrentDownloads) {
      await _executeDownload(updatedEpisode);
    } else {
      _queuedEpisodes.add(updatedEpisode);
      await _db.updateEpisodeDownloadState(
        epId,
        status: DownloadStatus.queued,
        progress: 0.0,
      );
      _emitEvent(
        DownloadTaskEvent(
          episodeId: epId,
          mediaUrl: updatedEpisode.mediaUrl,
          status: DownloadStatus.queued,
        ),
      );
    }
  }

  Future<void> _executeDownload(Episode episode) async {
    final epId = episode.id!;
    final cancelToken = CancelToken();
    _activeDownloads[epId] = cancelToken;

    await _db.updateEpisodeDownloadState(
      epId,
      status: DownloadStatus.downloading,
      progress: 0.0,
      downloadedBytes: 0,
      totalBytes: 0,
    );

    _emitEvent(
      DownloadTaskEvent(
        episodeId: epId,
        mediaUrl: episode.mediaUrl,
        status: DownloadStatus.downloading,
        progress: 0.0,
      ),
    );

    final downloadsDir = await getDownloadsDirectory();
    final fileName = _sanitizeFileName(episode.mediaUrl, epId);
    final finalFilePath = p.join(downloadsDir.path, fileName);
    final partFilePath = '$finalFilePath.part';

    try {
      final partFile = File(partFilePath);
      if (await partFile.exists()) {
        await partFile.delete();
      }

      await _dio.download(
        episode.mediaUrl,
        partFilePath,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final last = _lastProgressUpdate[epId];
          if (last != null && now.difference(last).inMilliseconds < 250 && received < total) {
            return;
          }
          _lastProgressUpdate[epId] = now;

          final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          _db.updateEpisodeDownloadState(
            epId,
            status: DownloadStatus.downloading,
            progress: progress,
            downloadedBytes: received,
            totalBytes: total > 0 ? total : 0,
          );
          _emitEvent(
            DownloadTaskEvent(
              episodeId: epId,
              mediaUrl: episode.mediaUrl,
              status: DownloadStatus.downloading,
              progress: progress,
              downloadedBytes: received,
              totalBytes: total > 0 ? total : 0,
            ),
          );
        },
      );

      // Verify and rename .part to final file
      final downloadedPart = File(partFilePath);
      if (await downloadedPart.exists() && await downloadedPart.length() > 0) {
        final finalFile = File(finalFilePath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await downloadedPart.rename(finalFilePath);
        final finalLength = await finalFile.length();

        await _db.updateEpisodeDownloadState(
          epId,
          status: DownloadStatus.downloaded,
          downloadPath: finalFilePath,
          progress: 1.0,
          downloadedBytes: finalLength,
          totalBytes: finalLength,
        );

        _emitEvent(
          DownloadTaskEvent(
            episodeId: epId,
            mediaUrl: episode.mediaUrl,
            status: DownloadStatus.downloaded,
            progress: 1.0,
            downloadedBytes: finalLength,
            totalBytes: finalLength,
            downloadPath: finalFilePath,
          ),
        );
      } else {
        throw Exception('Downloaded file is empty or missing');
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        await _cleanupPartFile(partFilePath);
        await _db.clearEpisodeDownload(epId);
        _emitEvent(
          DownloadTaskEvent(
            episodeId: epId,
            mediaUrl: episode.mediaUrl,
            status: DownloadStatus.none,
          ),
        );
      } else {
        await _cleanupPartFile(partFilePath);
        await _db.updateEpisodeDownloadState(
          epId,
          status: DownloadStatus.failed,
          progress: 0.0,
        );
        _emitEvent(
          DownloadTaskEvent(
            episodeId: epId,
            mediaUrl: episode.mediaUrl,
            status: DownloadStatus.failed,
            error: e.message ?? 'Download failed',
          ),
        );
      }
    } catch (e) {
      await _cleanupPartFile(partFilePath);
      await _db.updateEpisodeDownloadState(
        epId,
        status: DownloadStatus.failed,
        progress: 0.0,
      );
      _emitEvent(
        DownloadTaskEvent(
          episodeId: epId,
          mediaUrl: episode.mediaUrl,
          status: DownloadStatus.failed,
          error: e.toString(),
        ),
      );
    } finally {
      _activeDownloads.remove(epId);
      _lastProgressUpdate.remove(epId);
      _processNextQueueItem();
    }
  }

  Future<void> _cleanupPartFile(String partPath) async {
    try {
      final file = File(partPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void _processNextQueueItem() {
    if (_activeDownloads.length < maxConcurrentDownloads && _queuedEpisodes.isNotEmpty) {
      final next = _queuedEpisodes.removeAt(0);
      _executeDownload(next);
    }
  }

  Future<void> cancelDownload(int episodeId) async {
    if (_activeDownloads.containsKey(episodeId)) {
      _activeDownloads[episodeId]?.cancel('Cancelled by user');
      _activeDownloads.remove(episodeId);
      return;
    }

    final queuedIdx = _queuedEpisodes.indexWhere((e) => e.id == episodeId);
    if (queuedIdx != -1) {
      final removed = _queuedEpisodes.removeAt(queuedIdx);
      await _db.clearEpisodeDownload(episodeId);
      _emitEvent(
        DownloadTaskEvent(
          episodeId: episodeId,
          mediaUrl: removed.mediaUrl,
          status: DownloadStatus.none,
        ),
      );
    }
  }

  Future<void> deleteDownload(Episode episode) async {
    int? epId = episode.id;
    if (epId == null) {
      final found = await _db.getEpisodeByGuid(episode.guid);
      epId = found?.id;
    }
    if (epId == null) return;

    if (_activeDownloads.containsKey(epId)) {
      await cancelDownload(epId);
    } else {
      _queuedEpisodes.removeWhere((e) => e.id == epId);
    }

    if (episode.downloadPath != null) {
      try {
        final file = File(episode.downloadPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        if (kDebugMode) print('Error deleting download file: $e');
      }
    }

    await _db.clearEpisodeDownload(epId);
    _emitEvent(
      DownloadTaskEvent(
        episodeId: epId,
        mediaUrl: episode.mediaUrl,
        status: DownloadStatus.none,
        progress: 0.0,
      ),
    );
  }

  Future<int> clearAllDownloads() async {
    for (final token in _activeDownloads.values) {
      token.cancel('Clearing all downloads');
    }
    _activeDownloads.clear();
    _queuedEpisodes.clear();

    final downloaded = await _db.getDownloadedEpisodes();
    int deletedCount = 0;
    for (final ep in downloaded) {
      if (ep.downloadPath != null) {
        try {
          final file = File(ep.downloadPath!);
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        } catch (_) {}
      }
    }

    await _db.clearAllDownloadedEpisodes();
    for (final ep in downloaded) {
      if (ep.id != null) {
        _emitEvent(
          DownloadTaskEvent(
            episodeId: ep.id!,
            mediaUrl: ep.mediaUrl,
            status: DownloadStatus.none,
          ),
        );
      }
    }
    return deletedCount;
  }

  Future<void> verifyDownloadedFiles() async {
    final downloaded = await _db.getDownloadedEpisodes();
    for (final ep in downloaded) {
      if (ep.downloadPath == null || !await File(ep.downloadPath!).exists()) {
        if (ep.id != null) {
          await _db.clearEpisodeDownload(ep.id!);
          _emitEvent(
            DownloadTaskEvent(
              episodeId: ep.id!,
              mediaUrl: ep.mediaUrl,
              status: DownloadStatus.none,
            ),
          );
        }
      }
    }
  }

  Future<int> getTotalDownloadStorageBytes() async {
    int totalBytes = 0;

    // 1. Check all downloaded episodes in the database and their actual file sizes on disk
    try {
      final downloaded = await _db.getDownloadedEpisodes();
      for (final ep in downloaded) {
        if (ep.downloadPath != null && ep.downloadPath!.isNotEmpty) {
          try {
            final file = File(ep.downloadPath!);
            if (await file.exists()) {
              final len = await file.length();
              totalBytes += len;
              // Self-heal: if DB had downloadedBytes <= 0, update it in DB
              if (ep.id != null && ep.downloadedBytes <= 0 && len > 0) {
                await _db.updateEpisodeDownloadState(
                  ep.id!,
                  status: DownloadStatus.downloaded,
                  downloadPath: ep.downloadPath,
                  progress: 1.0,
                  downloadedBytes: len,
                  totalBytes: len,
                );
              }
              continue;
            }
          } catch (_) {}
        }
        if (ep.downloadedBytes > 0) {
          totalBytes += ep.downloadedBytes;
        }
      }
    } catch (_) {}

    if (totalBytes > 0) {
      return totalBytes;
    }

    // 2. Also check SQL sum
    try {
      final sqlSum = await _db.getTotalDownloadSizeBytes();
      if (sqlSum > 0) {
        return sqlSum;
      }
    } catch (_) {}

    // 3. Fallback: inspect actual downloads folder on disk
    try {
      final dir = await getDownloadsDirectory();
      if (await dir.exists()) {
        int diskBytes = 0;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File && !entity.path.endsWith('.part')) {
            diskBytes += await entity.length();
          }
        }
        return diskBytes;
      }
    } catch (_) {}

    return 0;
  }

  void _emitEvent(DownloadTaskEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}
