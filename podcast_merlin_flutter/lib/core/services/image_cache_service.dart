import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Helper service for background image caching and local file management.
class ImageCacheService {
  ImageCacheService._();

  static final CacheManager _cacheManager = DefaultCacheManager();

  /// Pre-fetches a single image URL into local disk cache.
  static Future<void> precacheImageUrl(String? url) async {
    if (url == null || url.trim().isEmpty) return;
    try {
      final uri = Uri.tryParse(url.trim());
      if (uri != null && (uri.isScheme('HTTP') || uri.isScheme('HTTPS'))) {
        await _cacheManager.downloadFile(url.trim());
      }
    } catch (e) {
      if (kDebugMode) {
        print('ImageCacheService: Failed to precache image $url: $e');
      }
    }
  }

  /// Batch pre-caches a collection of image URLs (with max concurrency of 4).
  static Future<void> precacheBatch(Iterable<String?> urls) async {
    final validUrls = urls
        .whereType<String>()
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && (u.startsWith('http://') || u.startsWith('https://')))
        .toSet();

    if (validUrls.isEmpty) return;

    final urlList = validUrls.toList();
    const batchSize = 4;
    for (var i = 0; i < urlList.length; i += batchSize) {
      final chunk = urlList.sublist(i, i + batchSize > urlList.length ? urlList.length : i + batchSize);
      await Future.wait(chunk.map((url) => precacheImageUrl(url)));
    }
  }

  /// Retrieves local cached file path for an image URL if available on disk.
  static Future<String?> getCachedFilePath(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    try {
      final fileInfo = await _cacheManager.getFileFromCache(url.trim());
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo.file.path;
      }
    } catch (e) {
      if (kDebugMode) {
        print('ImageCacheService: Error getting cached file path: $e');
      }
    }
    return null;
  }
}
