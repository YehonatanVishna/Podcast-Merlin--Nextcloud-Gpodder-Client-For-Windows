import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Helper service for persistent local disk image caching and pre-fetching.
class ImageCacheService {
  ImageCacheService._();

  static Directory? _cacheDir;
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
    ),
  );

  /// Resolves the persistent disk image cache directory in Application Support.
  static Future<Directory> _getCacheDir() async {
    if (_cacheDir != null && await _cacheDir!.exists()) return _cacheDir!;
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(appSupportDir.path, 'persistent_image_cache'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    } catch (_) {
      final temp = await getTemporaryDirectory();
      final dir = Directory(p.join(temp.path, 'persistent_image_cache'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    }
  }

  /// Deterministically hashes an image URL into a unique local filename.
  static String _hashUrl(String url) {
    final bytes = utf8.encode(url.trim());
    final hash = md5.convert(bytes).toString();
    final cleanPath = url.split('?').first.split('#').first.toLowerCase();
    String extension = '.img';
    if (cleanPath.endsWith('.png')) {
      extension = '.png';
    } else if (cleanPath.endsWith('.jpg') || cleanPath.endsWith('.jpeg')) {
      extension = '.jpg';
    } else if (cleanPath.endsWith('.svg')) {
      extension = '.svg';
    } else if (cleanPath.endsWith('.webp')) {
      extension = '.webp';
    }
    return '$hash$extension';
  }

  /// Checks if the image is already stored on persistent disk storage (0ms network lookup).
  static Future<File?> getCachedFile(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    try {
      final dir = await _getCacheDir();
      final filename = _hashUrl(url);
      final file = File(p.join(dir.path, filename));
      if (await file.exists()) {
        return file;
      }
    } catch (e) {
      if (kDebugMode) {
        print('ImageCacheService: Error checking file cache for $url: $e');
      }
    }
    return null;
  }

  /// Downloads image via Dio with timeout and saves directly to persistent disk storage.
  static Future<File?> downloadAndCache(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    final cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) return null;

    final existing = await getCachedFile(cleanUrl);
    if (existing != null) return existing;

    try {
      final dir = await _getCacheDir();
      final filename = _hashUrl(cleanUrl);
      final file = File(p.join(dir.path, filename));
      final tempFile = File(p.join(dir.path, '$filename.tmp'));

      await _dio.download(cleanUrl, tempFile.path);
      if (await tempFile.exists()) {
        await tempFile.rename(file.path);
        return file;
      }
    } catch (e) {
      if (kDebugMode) {
        print('ImageCacheService: Download failed for $cleanUrl: $e');
      }
    }
    return null;
  }

  /// Pre-fetches a single image URL into local persistent disk storage.
  static Future<void> precacheImageUrl(String? url) async {
    await downloadAndCache(url);
  }

  /// Batch pre-caches a collection of image URLs concurrently in background.
  static Future<void> precacheBatch(Iterable<String?> urls) async {
    final validUrls = urls
        .whereType<String>()
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && (u.startsWith('http://') || u.startsWith('https://')))
        .toSet();

    if (validUrls.isEmpty) return;

    final urlList = validUrls.toList();
    const batchSize = 6;
    for (var i = 0; i < urlList.length; i += batchSize) {
      final chunk = urlList.sublist(i, i + batchSize > urlList.length ? urlList.length : i + batchSize);
      await Future.wait(chunk.map((url) => precacheImageUrl(url)));
    }
  }

  /// Retrieves local cached file path for an image URL if available on disk.
  static Future<String?> getCachedFilePath(String? url) async {
    final file = await getCachedFile(url);
    return file?.path;
  }
}
