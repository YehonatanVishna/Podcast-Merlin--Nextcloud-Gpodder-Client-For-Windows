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
  int? lastEpisodeActionTimestamp;

  GPodderApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
                headers: {
                  'User-Agent': 'PodcastMerlin/2.0 (Flutter)',
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  String _formatBaseUrl(String serverUrl) {
    var url = serverUrl.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/index.php')) {
      url = url.substring(0, url.length - 10);
    }
    final lower = url.toLowerCase();
    if (lower.contains('gpodder.net')) {
      return url;
    }
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
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
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
    if (serverUrl.trim().isEmpty || username.trim().isEmpty || password.trim().isEmpty) {
      lastError = 'Server credentials not configured.';
      return null;
    }

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final options = _getAuthOptions(username, password);

      final queryParam = sinceTimestamp > 0 ? '?since=$sinceTimestamp' : '';
      final urlsToTry = <String>[
        '$baseUrl/subscriptions$queryParam',
        if (sinceTimestamp == 0) '$baseUrl/subscriptions?since=0',
      ];
      if (baseUrl.contains('/index.php/')) {
        urlsToTry.add('${baseUrl.replaceFirst('/index.php/', '/')}/subscriptions$queryParam');
      } else if (!baseUrl.contains('gpodder.net')) {
        urlsToTry.add('$baseUrl/index.php/apps/gpoddersync/subscriptions$queryParam');
      }
      final cleanServerUrl = serverUrl.trim().endsWith('/')
          ? serverUrl.trim().substring(0, serverUrl.trim().length - 1)
          : serverUrl.trim();
      urlsToTry.add('$cleanServerUrl/api/2/subscriptions/$username.json$queryParam');

      Response? response;
      DioException? lastDioException;

      for (final targetUrl in urlsToTry) {
        try {
          final res = await _dio.get(targetUrl, options: options);
          if (res.statusCode == 200 && res.data != null) {
            dynamic data = res.data;
            if (data is String) {
              final trimmed = data.trim();
              if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
                try {
                  data = jsonDecode(trimmed);
                } catch (_) {
                  data = null;
                }
              } else {
                data = null;
              }
            }
            if (data is Map || data is List) {
              response = res;
              break;
            }
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (dioErr.response?.statusCode == 404 ||
              dioErr.response?.statusCode == 400 ||
              dioErr.response?.statusCode == 405) {
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        if (lastDioException != null) {
          throw lastDioException;
        }
        lastError = 'Failed to fetch subscriptions from server';
        return null;
      }

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

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final payload = {
        'add': addUrls,
        'remove': removeUrls,
      };
      final urlsToTry = <String>[
        '$baseUrl/subscription_change/create',
        '$baseUrl/subscriptions',
      ];
      Response? response;
      DioException? lastDioException;
      for (final targetUrl in urlsToTry) {
        try {
          final res = await _dio.post(
            targetUrl,
            data: payload,
            options: _getAuthOptions(username, password),
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            response = res;
            break;
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (dioErr.response?.statusCode == 404) {
            continue;
          }
          rethrow;
        }
      }
      if (response != null) {
        lastError = null;
        return true;
      }
      if (lastDioException != null) throw lastDioException;
      lastError = 'Failed to upload subscriptions';
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
    lastEpisodeActionTimestamp = null;
    if (serverUrl.trim().isEmpty || username.trim().isEmpty || password.trim().isEmpty) {
      lastError = 'Server credentials not configured.';
      return [];
    }

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final options = _getAuthOptions(username, password).copyWith(
        receiveTimeout: const Duration(seconds: 90),
      );

      final queryParam = sinceTimestamp > 0 ? '?since=$sinceTimestamp' : '';
      final urlsToTry = <String>[
        '$baseUrl/episode_action$queryParam',
        if (sinceTimestamp == 0) '$baseUrl/episode_action?since=0',
      ];
      if (baseUrl.contains('/index.php/')) {
        urlsToTry.add('${baseUrl.replaceFirst('/index.php/', '/')}/episode_action$queryParam');
      } else if (!baseUrl.contains('gpodder.net')) {
        urlsToTry.add('$baseUrl/index.php/apps/gpoddersync/episode_action$queryParam');
      }
      final cleanServerUrl = serverUrl.trim().endsWith('/')
          ? serverUrl.trim().substring(0, serverUrl.trim().length - 1)
          : serverUrl.trim();
      urlsToTry.add('$cleanServerUrl/api/2/episodes/$username.json$queryParam');

      Response? response;
      DioException? lastDioException;

      for (final targetUrl in urlsToTry) {
        try {
          final res = await _dio.get(targetUrl, options: options);
          if (res.statusCode == 200 && res.data != null) {
            dynamic data = res.data;
            if (data is String) {
              final trimmed = data.trim();
              if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
                try {
                  data = jsonDecode(trimmed);
                } catch (_) {
                  data = null;
                }
              } else {
                data = null;
              }
            }
            if (data is Map || data is List) {
              response = res;
              break;
            }
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (dioErr.response?.statusCode == 404 ||
              dioErr.response?.statusCode == 400 ||
              dioErr.response?.statusCode == 405) {
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        if (lastDioException != null) {
          throw lastDioException;
        }
        lastError = 'Failed to fetch episode actions from server';
        return [];
      }

      dynamic decoded = response.data;
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }

      List rawActions = [];
      if (decoded is List) {
        rawActions = decoded;
      } else if (decoded is Map) {
        rawActions = (decoded['actions'] as List?) ??
            (decoded['episode_actions'] as List?) ??
            (decoded['episodeActions'] as List?) ??
            (decoded['data'] as List?) ??
            [];
        final tsVal = decoded['timestamp'];
        if (tsVal is num) {
          lastEpisodeActionTimestamp = tsVal.toInt();
        } else if (tsVal != null) {
          final s = tsVal.toString().trim();
          final parsedNum = num.tryParse(s);
          if (parsedNum != null) {
            lastEpisodeActionTimestamp = parsedNum.toInt();
          }
        }
      }

      lastError = null;
      final actions = <GPodderAction>[];
      for (final item in rawActions) {
        try {
          dynamic mapItem = item;
          if (mapItem is String) {
            try {
              mapItem = jsonDecode(mapItem);
            } catch (_) {}
          }
          if (mapItem is Map) {
            actions.add(GPodderAction.fromMap(Map<String, dynamic>.from(mapItem)));
          }
        } catch (e) {
          if (kDebugMode) print('Error parsing individual action: $e');
        }
      }

      if (lastEpisodeActionTimestamp == null && actions.isNotEmpty) {
        final maxActionTs = actions
            .map((a) => a.timestamp.millisecondsSinceEpoch ~/ 1000)
            .fold(0, (max, ts) => ts > max ? ts : max);
        if (maxActionTs > 0) {
          lastEpisodeActionTimestamp = maxActionTs;
        }
      }

      return actions;
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

    try {
      final baseUrl = _formatBaseUrl(serverUrl);
      final payload = actions.map((a) => a.toApiJson()).toList();
      final urlsToTry = <String>[
        '$baseUrl/episode_action/create',
        '$baseUrl/episode_actions',
      ];
      Response? response;
      DioException? lastDioException;
      for (final targetUrl in urlsToTry) {
        try {
          final res = await _dio.post(
            targetUrl,
            data: payload,
            options: _getAuthOptions(username, password),
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            response = res;
            break;
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (dioErr.response?.statusCode == 404) {
            continue;
          }
          rethrow;
        }
      }
      if (response != null) {
        lastError = null;
        return true;
      }
      if (lastDioException != null) throw lastDioException;
      lastError = 'Failed to upload episode actions';
      return false;
    } catch (e) {
      if (kDebugMode) print('uploadEpisodeActions error: $e');
      lastError = AppErrorFormatter.format(e);
      return false;
    }
  }
}
