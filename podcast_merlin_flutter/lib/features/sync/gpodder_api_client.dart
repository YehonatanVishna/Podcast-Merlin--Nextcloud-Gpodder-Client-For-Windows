import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../core/models/gpodder_action.dart';

class GPodderApiClient {
  final Dio _dio;

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
    if (!url.contains('/index.php/apps/gpodder')) {
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

  /// Check connectivity & credentials against Nextcloud gPodder server
  Future<bool> checkConnection({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final response = await _dio.get(
        '$baseUrl/subscriptions?since=2147483647',
        options: _getAuthOptions(username, password),
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('checkConnection error: $e');
      return false;
    }
  }

  /// Get subscriptions diff from server
  Future<Map<String, dynamic>?> fetchSubscriptions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
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
          final addList = decoded.map((e) => e.toString()).toList();
          return {
            'add': addList,
            'remove': <String>[],
            'timestamp': sinceTimestamp,
          };
        } else if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final addRaw = map['add'];
          final removeRaw = map['remove'];

          List<String> addList = [];
          if (addRaw is List) {
            addList = addRaw.map((e) => e.toString()).toList();
          } else if (addRaw is String && addRaw.isNotEmpty) {
            addList = [addRaw];
          }

          List<String> removeList = [];
          if (removeRaw is List) {
            removeList = removeRaw.map((e) => e.toString()).toList();
          } else if (removeRaw is String && removeRaw.isNotEmpty) {
            removeList = [removeRaw];
          }

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
    } catch (e) {
      if (kDebugMode) print('fetchSubscriptions error: $e');
    }
    return null;
  }

  /// Upload subscription add/remove actions to server
  Future<bool> uploadSubscriptionChanges({
    required String serverUrl,
    required String username,
    required String password,
    required List<String> addUrls,
    required List<String> removeUrls,
  }) async {
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
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      if (kDebugMode) print('uploadSubscriptionChanges error: $e');
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

        return rawActions
            .map((item) => GPodderAction.fromMap(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) print('fetchEpisodeActions error: $e');
    }
    return [];
  }

  /// Post queued episode actions to server
  Future<bool> uploadEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    required List<GPodderAction> actions,
  }) async {
    if (actions.isEmpty) return true;
    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final payload = actions.map((a) => a.toApiJson()).toList();
      final response = await _dio.post(
        '$baseUrl/episode_action/create',
        data: payload,
        options: _getAuthOptions(username, password),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      if (kDebugMode) print('uploadEpisodeActions error: $e');
      return false;
    }
  }
}
