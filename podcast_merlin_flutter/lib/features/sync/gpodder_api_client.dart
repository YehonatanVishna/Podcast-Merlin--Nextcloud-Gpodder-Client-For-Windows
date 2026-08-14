import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../core/models/gpodder_action.dart';
import '../../core/utils/error_formatter.dart';

class GPodderApiException implements Exception {
  final String message;
  final int? statusCode;

  GPodderApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class GPodderApiClient {
  final Dio _dio;
  String? lastError;

  GPodderApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent': 'PodcastMerlin/2.0 (Flutter)',
                  'Content-Type': 'application/json',
                },
              ),
            );

  String _formatBaseUrl(String serverUrl) {
    var url = serverUrl.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final lower = url.toLowerCase();
    if (!lower.contains('/apps/gpoddersync') && !lower.contains('/apps/gpodder')) {
      url = '$url/index.php/apps/gpoddersync';
    }
    return url;
  }

  Options _getAuthOptions(String username, String password) {
    final authBytes = utf8.encode('$username:$password');
    final authHeader = 'Basic ${base64Encode(authBytes)}';
    return Options(
      headers: {
        'Authorization': authHeader,
      },
    );
  }

  List<String> _extractUrls(dynamic raw) {
    final urls = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is String) {
          final trimmed = item.trim();
          if (trimmed.isNotEmpty) urls.add(trimmed);
        } else if (item is Map) {
          final url = (item['url'] ?? item['rss_url'] ?? item['rssUrl'] ?? item['feed'] ?? item['link'] ?? '').toString().trim();
          if (url.isNotEmpty) urls.add(url);
        }
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      urls.add(raw.trim());
    } else if (raw is Map) {
      final url = (raw['url'] ?? raw['rss_url'] ?? raw['rssUrl'] ?? raw['feed'] ?? raw['link'] ?? '').toString().trim();
      if (url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  /// Fast connectivity ping check prior to any server HTTP request
  Future<bool> pingServer({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    if (serverUrl.trim().isEmpty || username.trim().isEmpty || password.trim().isEmpty) {
      lastError = 'Server credentials not configured.';
      return false;
    }
    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final response = await _dio.get(
        '$baseUrl/subscriptions?since=2147483647',
        options: _getAuthOptions(username, password).copyWith(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      if (response.statusCode == 200) {
        lastError = null;
        return true;
      }
      lastError = 'gPodder server ping returned HTTP status ${response.statusCode}';
      return false;
    } catch (e) {
      if (kDebugMode) print('pingServer error: $e');
      lastError = AppErrorFormatter.format(e);
      return false;
    }
  }

  /// Check connectivity & credentials against Nextcloud gPodder server, returning detailed error or null if success
  Future<String?> testConnectionDetailed({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    if (serverUrl.trim().isEmpty) {
      return 'Server URL cannot be empty.';
    }
    if (username.trim().isEmpty || password.trim().isEmpty) {
      return 'Username and password cannot be empty.';
    }
    final ok = await pingServer(serverUrl: serverUrl, username: username, password: password);
    return ok ? null : (lastError ?? 'Connection failed');
  }

  /// Check connectivity & credentials against Nextcloud gPodder server
  Future<bool> checkConnection({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    return pingServer(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }

  /// Get subscriptions diff from server
  Future<Map<String, dynamic>?> fetchSubscriptions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    final isOnline = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!isOnline) {
      return null;
    }

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final response = await _dio.get(
        '$baseUrl/subscriptions?since=$sinceTimestamp',
        options: _getAuthOptions(username, password),
      );

      if (response.statusCode == 200 && response.data != null) {
        dynamic decoded = response.data;
        if (decoded is String) {
          try {
            decoded = jsonDecode(decoded);
          } catch (_) {}
        }

        if (decoded is List) {
          lastError = null;
          final addList = _extractUrls(decoded);
          return {
            'add': addList,
            'remove': <String>[],
            'timestamp': sinceTimestamp,
          };
        } else if (decoded is Map) {
          lastError = null;
          final map = Map<String, dynamic>.from(decoded);
          final addRaw = map['add'] ?? map['subscriptions'] ?? map['urls'] ?? map['feeds'];
          final removeRaw = map['remove'];

          final addList = _extractUrls(addRaw);
          final removeList = _extractUrls(removeRaw);

          int parsedTs = sinceTimestamp;
          final tsRaw = map['timestamp'];
          if (tsRaw is num) {
            parsedTs = tsRaw.toInt();
          } else if (tsRaw != null) {
            parsedTs = int.tryParse(tsRaw.toString()) ?? sinceTimestamp;
          }

          return {
            'add': addList,
            'remove': removeList,
            'timestamp': parsedTs,
          };
        }
      }
      lastError = 'Server returned HTTP status ${response.statusCode}';
      return null;
    } catch (e) {
      if (kDebugMode) print('fetchSubscriptions error: $e');
      lastError = AppErrorFormatter.format(e);
      return null;
    }
  }

  /// Upload subscription add/remove actions to server
  Future<bool> uploadSubscriptionChanges({
    required String serverUrl,
    required String username,
    required String password,
    required List<String> addUrls,
    required List<String> removeUrls,
  }) async {
    if (addUrls.isEmpty && removeUrls.isEmpty) return true;

    final isOnline = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!isOnline) {
      return false;
    }

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final payload = {
        'add': addUrls,
        'remove': removeUrls,
      };
      final response = await _dio.post(
        '$baseUrl/subscriptions',
        data: payload,
        options: _getAuthOptions(username, password),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        lastError = null;
        return true;
      }
      lastError = 'Failed to upload subscriptions (HTTP ${response.statusCode})';
      return false;
    } catch (e) {
      if (kDebugMode) print('uploadSubscriptionChanges error: $e');
      lastError = AppErrorFormatter.format(e);
      return false;
    }
  }

  /// Fetch remote episode actions since timestamp
  Future<List<GPodderAction>> fetchEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    final isOnline = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!isOnline) {
      return [];
    }

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final response = await _dio.get(
        '$baseUrl/episode_action?since=$sinceTimestamp',
        options: _getAuthOptions(username, password),
      );

      if (response.statusCode == 200 && response.data != null) {
        dynamic decoded = response.data;
        if (decoded is String) {
          try {
            decoded = jsonDecode(decoded);
          } catch (_) {}
        }

        List rawActions = [];
        if (decoded is Map) {
          rawActions = (decoded['actions'] as List?) ?? [];
        } else if (decoded is List) {
          rawActions = decoded;
        }

        lastError = null;
        return rawActions
            .map((item) => GPodderAction.fromMap(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      lastError = 'Failed to fetch episode actions (HTTP ${response.statusCode})';
      return [];
    } catch (e) {
      if (kDebugMode) print('fetchEpisodeActions error: $e');
      lastError = AppErrorFormatter.format(e);
      return [];
    }
  }

  /// Post queued episode actions to server
  Future<bool> uploadEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    required List<GPodderAction> actions,
  }) async {
    if (actions.isEmpty) return true;

    final isOnline = await pingServer(serverUrl: serverUrl, username: username, password: password);
    if (!isOnline) {
      return false;
    }

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final payload = actions.map((a) => a.toApiJson()).toList();
      final response = await _dio.post(
        '$baseUrl/episode_action/create',
        data: payload,
        options: _getAuthOptions(username, password),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        lastError = null;
        return true;
      }
      lastError = 'Failed to upload episode actions (HTTP ${response.statusCode})';
      return false;
    } catch (e) {
      if (kDebugMode) print('uploadEpisodeActions error: $e');
      lastError = AppErrorFormatter.format(e);
      return false;
    }
  }
}
