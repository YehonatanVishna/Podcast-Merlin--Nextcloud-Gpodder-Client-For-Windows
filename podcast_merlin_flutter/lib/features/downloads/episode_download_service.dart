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
  final String? episodeTitle;
  final String? imageUrl;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final int bytesPerSecond;
  final int? estimatedSecondsRemaining;
  final int retryAttempt;
  final String? downloadPath;
  final String? error;

  const DownloadTaskEvent({
    required this.episodeId,
    required this.mediaUrl,
    this.episodeTitle,
    this.imageUrl,
    required this.status,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.estimatedSecondsRemaining,
    this.retryAttempt = 0,
    this.downloadPath,
    this.error,
  });

  @override
  String toString() =>
      'DownloadTaskEvent(ep: $episodeId, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%, speed: $bytesPerSecond B/s)';
}

class EpisodeDownloadService {
  final DatabaseHelper _db;
  final Dio _dio;
  final int maxConcurrentDownloads;
  final Future<Directory> Function()? _customDirResolver;

  final Map<int, CancelToken> _activeDownloads = {};
  final Set<int> _pausedEpisodeIds = <int>{};
  final List<Episode> _queuedEpisodes = [];
  final Map<int, DateTime> _lastProgressUpdate = {};
  final Map<int, DownloadTaskEvent> _currentTasks = {};

  final StreamController<DownloadTaskEvent> _eventController =
      StreamController<DownloadTaskEvent>.broadcast();

  Stream<DownloadTaskEvent> get onDownloadEvent => _eventController.stream;
  Map<int, DownloadTaskEvent> get currentTasks => Map.unmodifiable(_currentTasks);
  int get activeAndQueuedCount => _activeDownloads.length + _queuedEpisodes.length;
  List<Episode> get queuedEpisodes => List.unmodifiable(_queuedEpisodes);

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
    _currentTasks.clear();
    _eventController.close();
    _dio.close(force: true);
  }

  bool isEpisodeActive(int episodeId) => _activeDownloads.containsKey(episodeId);

  bool isEpisodeQueued(int episodeId) =>
      _queuedEpisodes.any((e) => e.id == episodeId);

  bool isEpisodePaused(int episodeId) {
    final task = _currentTasks[episodeId];
    return task?.status == DownloadStatus.paused;
  }

  DownloadStatus getEpisodeStatus(Episode episode) {
    final epId = episode.id;
    if (epId != null) {
      if (isEpisodeActive(epId)) return DownloadStatus.downloading;
      if (isEpisodeQueued(epId)) return DownloadStatus.queued;
      final cachedTask = _currentTasks[epId];
      if (cachedTask != null) return cachedTask.status;
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
    _pausedEpisodeIds.remove(epId);

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
      unawaited(_executeDownload(updatedEpisode));
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
          episodeTitle: updatedEpisode.title,
          imageUrl: updatedEpisode.imageUrl,
          status: DownloadStatus.queued,
        ),
      );
    }
  }

  Future<void> _executeDownload(Episode episode) async {
    final epId = episode.id!;
    final cancelToken = CancelToken();
    _activeDownloads[epId] = cancelToken;

    final downloadsDir = await getDownloadsDirectory();
    final fileName = _sanitizeFileName(episode.mediaUrl, epId);
    final finalFilePath = p.join(downloadsDir.path, fileName);
    final partFilePath = '$finalFilePath.part';

    int retryCount = 0;
    const int maxRetries = 3;

    await _db.updateEpisodeDownloadState(
      epId,
      status: DownloadStatus.downloading,
      progress: 0.0,
      clearError: true,
    );

    _emitEvent(
      DownloadTaskEvent(
        episodeId: epId,
        mediaUrl: episode.mediaUrl,
        episodeTitle: episode.title,
        imageUrl: episode.imageUrl,
        status: DownloadStatus.downloading,
        progress: 0.0,
      ),
    );

    try {
      while (retryCount <= maxRetries) {
        RandomAccessFile? raf;
        try {
          final partFile = File(partFilePath);
          int startBytes = 0;
          if (await partFile.exists()) {
            startBytes = await partFile.length();
          }

          final Map<String, dynamic> headers = {};
          if (startBytes > 0) {
            headers['Range'] = 'bytes=$startBytes-';
          }

          final response = await _dio.get<ResponseBody>(
            episode.mediaUrl,
            options: Options(
              responseType: ResponseType.stream,
              headers: headers.isNotEmpty ? headers : null,
              validateStatus: (status) =>
                  status != null && ((status >= 200 && status < 300) || status == 416),
            ),
            cancelToken: cancelToken,
          );

          if (response.statusCode == 416) {
            if (await partFile.exists()) {
              await partFile.delete();
            }
            startBytes = 0;
            retryCount++;
            continue;
          }

          final isPartial = response.statusCode == 206;
          if (!isPartial && startBytes > 0) {
            startBytes = 0;
            if (await partFile.exists()) {
              await partFile.delete();
            }
          }

          int contentLength = -1;
          final contentLengthHeader = response.headers.value(Headers.contentLengthHeader);
          if (contentLengthHeader != null) {
            contentLength = int.tryParse(contentLengthHeader) ?? -1;
          }

          int totalBytes = 0;
          final contentRangeHeader = response.headers.value('content-range');
          if (contentRangeHeader != null) {
            final match = RegExp(r'/(\d+)').firstMatch(contentRangeHeader);
            if (match != null) {
              totalBytes = int.tryParse(match.group(1)!) ?? 0;
            }
          }
          if (totalBytes == 0) {
            totalBytes = contentLength > 0
                ? (startBytes + contentLength)
                : (episode.totalBytes > 0 ? episode.totalBytes : 0);
          }

          raf = await partFile.open(
            mode: isPartial ? FileMode.writeOnlyAppend : FileMode.writeOnly,
          );

          int receivedBytes = startBytes;
          DateTime lastSampleTime = DateTime.now();
          int lastSampleBytes = receivedBytes;
          int speedBytesPerSecond = 0;

          await for (final chunk in response.data!.stream) {
            if (cancelToken.isCancelled || _pausedEpisodeIds.contains(epId)) {
              break;
            }
            raf.writeFromSync(chunk);
            receivedBytes += chunk.length;

            final now = DateTime.now();
            final deltaMs = now.difference(lastSampleTime).inMilliseconds;
            if (deltaMs >= 500) {
              final deltaBytes = receivedBytes - lastSampleBytes;
              final currentSpeed = ((deltaBytes / deltaMs) * 1000).round();
              speedBytesPerSecond = speedBytesPerSecond == 0
                  ? currentSpeed
                  : ((speedBytesPerSecond * 0.7) + (currentSpeed * 0.3)).round();
              lastSampleTime = now;
              lastSampleBytes = receivedBytes;
            }

            final lastDbUpdate = _lastProgressUpdate[epId];
            final shouldUpdateDb = lastDbUpdate == null ||
                now.difference(lastDbUpdate).inMilliseconds >= 250 ||
                (totalBytes > 0 && receivedBytes >= totalBytes);

            if (shouldUpdateDb) {
              _lastProgressUpdate[epId] = now;
              final progress =
                  totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
              final remainingBytes =
                  totalBytes > receivedBytes ? (totalBytes - receivedBytes) : 0;
              final etaSeconds = (speedBytesPerSecond > 0 && remainingBytes > 0)
                  ? (remainingBytes / speedBytesPerSecond).ceil()
                  : null;

              await _db.updateEpisodeDownloadState(
                epId,
                status: DownloadStatus.downloading,
                progress: progress,
                downloadedBytes: receivedBytes,
                totalBytes: totalBytes,
              );

              _emitEvent(
                DownloadTaskEvent(
                  episodeId: epId,
                  mediaUrl: episode.mediaUrl,
                  episodeTitle: episode.title,
                  imageUrl: episode.imageUrl,
                  status: DownloadStatus.downloading,
                  progress: progress,
                  downloadedBytes: receivedBytes,
                  totalBytes: totalBytes,
                  bytesPerSecond: speedBytesPerSecond,
                  estimatedSecondsRemaining: etaSeconds,
                  retryAttempt: retryCount,
                ),
              );
            }
          }

          await raf.close();
          raf = null;

          if (cancelToken.isCancelled || _pausedEpisodeIds.contains(epId)) {
            if (_pausedEpisodeIds.contains(epId)) {
              await _db.updateEpisodeDownloadState(
                epId,
                status: DownloadStatus.paused,
              );
              _emitEvent(
                DownloadTaskEvent(
                  episodeId: epId,
                  mediaUrl: episode.mediaUrl,
                  status: DownloadStatus.paused,
                ),
              );
            } else {
              await _cleanupPartFile(partFilePath);
              await _db.clearEpisodeDownload(epId);
              _emitEvent(
                DownloadTaskEvent(
                  episodeId: epId,
                  mediaUrl: episode.mediaUrl,
                  status: DownloadStatus.none,
                ),
              );
            }
            return;
          }

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
              clearError: true,
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
            return;
          } else {
            throw Exception('Downloaded file is empty or missing');
          }
        } on DioException catch (e) {
          if (raf != null) {
            try {
              await raf.close();
            } catch (_) {}
            raf = null;
          }

          final isCancelled = CancelToken.isCancel(e) || cancelToken.isCancelled;
          final isPaused = _pausedEpisodeIds.contains(epId) ||
              (CancelToken.isCancel(e) && (e.error == 'paused_by_user' || e.message == 'paused_by_user'));

          if (isCancelled || isPaused) {
            if (isPaused) {
              await _db.updateEpisodeDownloadState(
                epId,
                status: DownloadStatus.paused,
              );
              _emitEvent(
                DownloadTaskEvent(
                  episodeId: epId,
                  mediaUrl: episode.mediaUrl,
                  status: DownloadStatus.paused,
                ),
              );
            } else {
              await _cleanupPartFile(partFilePath);
              await _db.clearEpisodeDownload(epId);
              _emitEvent(
                DownloadTaskEvent(
                  episodeId: epId,
                  mediaUrl: episode.mediaUrl,
                  status: DownloadStatus.none,
                ),
              );
            }
            return;
          }

          final statusCode = e.response?.statusCode;
          final isPermanent = statusCode != null &&
              (statusCode == 404 || statusCode == 403 || statusCode == 401 || statusCode == 410);

          if (isPermanent || retryCount >= maxRetries) {
            final errText = _formatDownloadError(e);
            await _db.updateEpisodeDownloadState(
              epId,
              status: DownloadStatus.failed,
              progress: 0.0,
              error: errText,
            );
            _emitEvent(
              DownloadTaskEvent(
                episodeId: epId,
                mediaUrl: episode.mediaUrl,
                status: DownloadStatus.failed,
                error: errText,
              ),
            );
            return;
          }

          retryCount++;
          final delayMs = 250 * (1 << (retryCount - 1));
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        } catch (e) {
          if (raf != null) {
            try {
              await raf.close();
            } catch (_) {}
            raf = null;
          }

          final isCancelled = cancelToken.isCancelled;
          final isPaused = _pausedEpisodeIds.contains(epId);

          if (isCancelled || isPaused) {
            if (isPaused) {
              await _db.updateEpisodeDownloadState(
                epId,
                status: DownloadStatus.paused,
              );
              _emitEvent(
                DownloadTaskEvent(
                  episodeId: epId,
                  mediaUrl: episode.mediaUrl,
                  status: DownloadStatus.paused,
                ),
              );
            } else {
              await _cleanupPartFile(partFilePath);
              await _db.clearEpisodeDownload(epId);
              _emitEvent(
                DownloadTaskEvent(
                  episodeId: epId,
                  mediaUrl: episode.mediaUrl,
                  status: DownloadStatus.none,
                ),
              );
            }
            return;
          }

          if (retryCount >= maxRetries) {
            final errText = e.toString();
            await _db.updateEpisodeDownloadState(
              epId,
              status: DownloadStatus.failed,
              progress: 0.0,
              error: errText,
            );
            _emitEvent(
              DownloadTaskEvent(
                episodeId: epId,
                mediaUrl: episode.mediaUrl,
                status: DownloadStatus.failed,
                error: errText,
              ),
            );
            return;
          }

          retryCount++;
          final delayMs = 250 * (1 << (retryCount - 1));
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        } finally {
          if (raf != null) {
            try {
              await raf.close();
            } catch (_) {}
          }
        }
      }
    } finally {
      _activeDownloads.remove(epId);
      _lastProgressUpdate.remove(epId);
      _processNextQueueItem();
    }
  }

  String _formatDownloadError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timed out';
        case DioExceptionType.connectionError:
          return 'Network connection failed';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code == 404) return 'Audio file not found on server (404)';
          if (code == 403) return 'Access denied by server (403)';
          if (code != null && code >= 500) return 'Server error ($code)';
          return 'HTTP error ($code)';
        default:
          return error.message ?? 'Download failed';
      }
    }
    return error.toString();
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

  Future<void> pauseDownload(int episodeId) async {
    _pausedEpisodeIds.add(episodeId);
    if (_activeDownloads.containsKey(episodeId)) {
      _activeDownloads[episodeId]?.cancel('paused_by_user');
      await _db.updateEpisodeDownloadState(
        episodeId,
        status: DownloadStatus.paused,
      );
      _emitEvent(
        DownloadTaskEvent(
          episodeId: episodeId,
          mediaUrl: _currentTasks[episodeId]?.mediaUrl ?? '',
          status: DownloadStatus.paused,
        ),
      );
      return;
    }

    final queuedIdx = _queuedEpisodes.indexWhere((e) => e.id == episodeId);
    if (queuedIdx != -1) {
      final removed = _queuedEpisodes.removeAt(queuedIdx);
      await _db.updateEpisodeDownloadState(
        episodeId,
        status: DownloadStatus.paused,
      );
      _emitEvent(
        DownloadTaskEvent(
          episodeId: episodeId,
          mediaUrl: removed.mediaUrl,
          status: DownloadStatus.paused,
        ),
      );
    }
  }

  Future<void> resumeDownload(Episode episode) async {
    int? epId = episode.id;
    if (epId == null) {
      final found = await _db.getEpisodeByGuid(episode.guid);
      epId = found?.id;
    }
    if (epId == null) return;
    _pausedEpisodeIds.remove(epId);

    final updated = episode.copyWith(id: epId, downloadStatus: DownloadStatus.queued);
    if (isEpisodeActive(epId) || isEpisodeQueued(epId)) return;

    if (_activeDownloads.length < maxConcurrentDownloads) {
      unawaited(_executeDownload(updated));
    } else {
      _queuedEpisodes.add(updated);
      await _db.updateEpisodeDownloadState(
        epId,
        status: DownloadStatus.queued,
        clearError: true,
      );
      _emitEvent(
        DownloadTaskEvent(
          episodeId: epId,
          mediaUrl: updated.mediaUrl,
          episodeTitle: updated.title,
          imageUrl: updated.imageUrl,
          status: DownloadStatus.queued,
        ),
      );
    }
  }

  Future<void> pauseAll() async {
    final activeIds = List<int>.from(_activeDownloads.keys);
    for (final id in activeIds) {
      await pauseDownload(id);
    }
    final queued = List<Episode>.from(_queuedEpisodes);
    for (final ep in queued) {
      if (ep.id != null) {
        await pauseDownload(ep.id!);
      }
    }
  }

  Future<void> resumeAll() async {
    final paused = await _db.getPausedEpisodes();
    for (final ep in paused) {
      await resumeDownload(ep);
    }
  }

  Future<void> retryFailed(Episode episode) async {
    int? epId = episode.id;
    if (epId == null) {
      final found = await _db.getEpisodeByGuid(episode.guid);
      epId = found?.id;
    }
    if (epId == null) return;

    await _db.updateEpisodeDownloadState(
      epId,
      status: DownloadStatus.queued,
      progress: 0.0,
      clearError: true,
    );
    await startDownload(episode.copyWith(id: epId, clearDownloadError: true));
  }

  Future<void> retryAllFailed() async {
    final failed = await _db.getFailedEpisodes();
    for (final ep in failed) {
      await retryFailed(ep);
    }
  }

  Future<void> cancelAllActive() async {
    final activeIds = List<int>.from(_activeDownloads.keys);
    for (final id in activeIds) {
      await cancelDownload(id);
    }
    final queued = List<Episode>.from(_queuedEpisodes);
    for (final ep in queued) {
      if (ep.id != null) {
        await cancelDownload(ep.id!);
      }
    }
  }

  Future<void> cancelDownload(int episodeId) async {
    _pausedEpisodeIds.remove(episodeId);
    if (_activeDownloads.containsKey(episodeId)) {
      _activeDownloads[episodeId]?.cancel('Cancelled by user');
      await _db.clearEpisodeDownload(episodeId);
      _emitEvent(
        DownloadTaskEvent(
          episodeId: episodeId,
          mediaUrl: _currentTasks[episodeId]?.mediaUrl ?? '',
          status: DownloadStatus.none,
        ),
      );
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

    try {
      final dir = await getDownloadsDirectory();
      final fileName = _sanitizeFileName(episode.mediaUrl, epId);
      final partFile = File(p.join(dir.path, '$fileName.part'));
      if (partFile.existsSync()) {
        partFile.deleteSync();
      }
    } catch (_) {}

    if (episode.downloadPath != null) {
      try {
        final file = File(episode.downloadPath!);
        if (file.existsSync()) {
          file.deleteSync();
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

  Future<int> deleteMultipleDownloads(Iterable<Episode> episodes) async {
    int deletedCount = 0;
    for (final ep in episodes) {
      await deleteDownload(ep);
      deletedCount++;
    }
    return deletedCount;
  }

  Future<int> deleteDownloadsByIds(Iterable<int> episodeIds) async {
    int deletedCount = 0;
    for (final id in episodeIds) {
      final ep = await _db.getEpisodeById(id);
      if (ep != null) {
        await deleteDownload(ep);
        deletedCount++;
      }
    }
    return deletedCount;
  }

  Future<int> clearAllDownloads() async {
    for (final token in _activeDownloads.values) {
      token.cancel('Clearing all downloads');
    }
    _activeDownloads.clear();
    _queuedEpisodes.clear();
    _currentTasks.clear();

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

  Future<void> reconcileOnStartup() async {
    // 1. Reconcile any interrupted downloads in DB from a previous crash/exit
    await _db.reconcileInterruptedEpisodes();

    // 2. Clean up orphaned .part files
    try {
      final dir = await getDownloadsDirectory();
      if (await dir.exists()) {
        final activeDbList = await _db.getActiveOrQueuedEpisodes();
        final pausedDbList = await _db.getPausedEpisodes();
        final validEpIds = {
          ...activeDbList.map((e) => e.id),
          ...pausedDbList.map((e) => e.id),
        };

        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File && entity.path.endsWith('.part')) {
            final baseName = p.basename(entity.path);
            final match = RegExp(r'^ep_(\d+)_').firstMatch(baseName);
            if (match != null) {
              final id = int.tryParse(match.group(1)!);
              if (id != null && !validEpIds.contains(id)) {
                await entity.delete();
              }
            } else {
              await entity.delete();
            }
          }
        }
      }
    } catch (_) {}

    // 3. Verify downloaded files and self-heal missing entries
    await verifyDownloadedFiles();

    // 4. Populate currentTasks for paused episodes so Queue tab displays them with title and art
    final pausedDbList = await _db.getPausedEpisodes();
    for (final ep in pausedDbList) {
      if (ep.id != null) {
        _emitEvent(
          DownloadTaskEvent(
            episodeId: ep.id!,
            mediaUrl: ep.mediaUrl,
            episodeTitle: ep.title,
            imageUrl: ep.imageUrl,
            status: DownloadStatus.paused,
            progress: ep.downloadProgress,
            downloadedBytes: ep.downloadedBytes,
            totalBytes: ep.totalBytes,
          ),
        );
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
                  clearError: true,
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
    final prev = _currentTasks[event.episodeId];
    final mergedEvent = DownloadTaskEvent(
      episodeId: event.episodeId,
      mediaUrl: event.mediaUrl.isNotEmpty ? event.mediaUrl : (prev?.mediaUrl ?? ''),
      episodeTitle: event.episodeTitle ?? prev?.episodeTitle,
      imageUrl: event.imageUrl ?? prev?.imageUrl,
      status: event.status,
      progress: event.progress,
      downloadedBytes: event.downloadedBytes,
      totalBytes: event.totalBytes,
      bytesPerSecond: event.bytesPerSecond,
      estimatedSecondsRemaining: event.estimatedSecondsRemaining,
      retryAttempt: event.retryAttempt,
      downloadPath: event.downloadPath ?? prev?.downloadPath,
      error: event.error,
    );

    if (mergedEvent.status == DownloadStatus.downloaded || mergedEvent.status == DownloadStatus.none) {
      _currentTasks.remove(mergedEvent.episodeId);
    } else {
      _currentTasks[mergedEvent.episodeId] = mergedEvent;
    }

    if (!_eventController.isClosed) {
      _eventController.add(mergedEvent);
    }
  }
}
