import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:podcast_merlin_flutter/core/models/gpodder_action.dart';

/// In-process Mock HTTP Server implementing the gPodder / Nextcloud gPodder API protocol.
class MockGPodderServer {
  HttpServer? _server;
  final Set<String> _subscriptions = {};
  final List<GPodderAction> _episodeActions = [];
  final List<_SubscriptionChange> _subscriptionHistory = [];

  String expectedUsername;
  String expectedPassword;
  int simulatedErrorCode = 0;

  MockGPodderServer({
    this.expectedUsername = 'testuser',
    this.expectedPassword = 'testpass',
  });

  /// Get base URL of the running mock server, e.g. http://127.0.0.1:54321
  String get baseUrl {
    if (_server == null) {
      throw StateError('MockGPodderServer is not running. Call start() first.');
    }
    return 'http://${_server!.address.host}:${_server!.port}';
  }

  int get port => _server?.port ?? 0;

  /// Start mock HTTP server on an ephemeral loopback port
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
  }

  /// Stop the mock HTTP server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Reset internal state
  void reset() {
    _subscriptions.clear();
    _episodeActions.clear();
    _subscriptionHistory.clear();
    simulatedErrorCode = 0;
  }

  /// Seed initial subscriptions
  void seedSubscriptions({List<String>? add, List<String>? remove}) {
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (add != null) {
      for (final url in add) {
        _subscriptions.add(url);
        _subscriptionHistory.add(_SubscriptionChange(url, 'add', nowTs));
      }
    }
    if (remove != null) {
      for (final url in remove) {
        _subscriptions.remove(url);
        _subscriptionHistory.add(_SubscriptionChange(url, 'remove', nowTs));
      }
    }
  }

  /// Seed initial episode actions
  void seedEpisodeActions(List<GPodderAction> actions) {
    _episodeActions.addAll(actions);
  }

  /// Inspect active subscriptions
  Set<String> getStoredSubscriptions() => Set.unmodifiable(_subscriptions);

  /// Inspect stored episode actions
  List<GPodderAction> getStoredEpisodeActions() => List.unmodifiable(_episodeActions);

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;

    if (simulatedErrorCode > 0) {
      response.statusCode = simulatedErrorCode;
      response.write(jsonEncode({'error': 'Simulated server error'}));
      await response.close();
      return;
    }

    // Basic Auth Check
    final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
    if (!_validateAuth(authHeader)) {
      response.statusCode = HttpStatus.unauthorized;
      response.write(jsonEncode({'error': 'Unauthorized'}));
      await response.close();
      return;
    }

    final path = request.uri.path;
    final queryParams = request.uri.queryParameters;

    try {
      if (path.endsWith('/subscriptions')) {
        if (request.method == 'GET') {
          await _handleGetSubscriptions(queryParams, response);
        } else if (request.method == 'POST') {
          await _handlePostSubscriptions(request, response);
        } else {
          response.statusCode = HttpStatus.methodNotAllowed;
        }
      } else if (path.endsWith('/episode_action')) {
        if (request.method == 'GET') {
          await _handleGetEpisodeActions(queryParams, response);
        } else {
          response.statusCode = HttpStatus.methodNotAllowed;
        }
      } else if (path.endsWith('/episode_action/create')) {
        if (request.method == 'POST') {
          await _handlePostEpisodeActions(request, response);
        } else {
          response.statusCode = HttpStatus.methodNotAllowed;
        }
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write(jsonEncode({'error': 'Not found: $path'}));
      }
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await response.close();
    }
  }

  bool _validateAuth(String? authHeader) {
    if (authHeader == null || !authHeader.startsWith('Basic ')) return false;
    final base64Credentials = authHeader.substring(6).trim();
    try {
      final decoded = utf8.decode(base64Decode(base64Credentials));
      final parts = decoded.split(':');
      if (parts.length != 2) return false;
      return parts[0] == expectedUsername && parts[1] == expectedPassword;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleGetSubscriptions(
    Map<String, String> queryParams,
    HttpResponse response,
  ) async {
    final sinceStr = queryParams['since'] ?? '0';
    final sinceTs = int.tryParse(sinceStr) ?? 0;
    final currentTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (sinceTs == 0) {
      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode({
        'add': _subscriptions.toList(),
        'remove': <String>[],
        'timestamp': currentTs,
      }));
      return;
    }

    final addList = <String>[];
    final removeList = <String>[];

    for (final change in _subscriptionHistory) {
      if (change.timestamp >= sinceTs) {
        if (change.action == 'add') {
          addList.add(change.url);
        } else if (change.action == 'remove') {
          removeList.add(change.url);
        }
      }
    }

    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({
      'add': addList,
      'remove': removeList,
      'timestamp': currentTs,
    }));
  }

  Future<void> _handlePostSubscriptions(
    HttpRequest request,
    HttpResponse response,
  ) async {
    final content = await utf8.decoder.bind(request).join();
    final Map<String, dynamic> body = jsonDecode(content);
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final addList = (body['add'] as List?)?.cast<String>() ?? [];
    final removeList = (body['remove'] as List?)?.cast<String>() ?? [];

    for (final url in addList) {
      _subscriptions.add(url);
      _subscriptionHistory.add(_SubscriptionChange(url, 'add', nowTs));
    }
    for (final url in removeList) {
      _subscriptions.remove(url);
      _subscriptionHistory.add(_SubscriptionChange(url, 'remove', nowTs));
    }

    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({'timestamp': nowTs}));
  }

  Future<void> _handleGetEpisodeActions(
    Map<String, String> queryParams,
    HttpResponse response,
  ) async {
    final sinceStr = queryParams['since'] ?? '0';
    final sinceTs = int.tryParse(sinceStr) ?? 0;

    final filtered = _episodeActions.where((a) {
      final actTs = a.timestamp.millisecondsSinceEpoch ~/ 1000;
      return actTs >= sinceTs;
    }).map((a) => a.toApiJson()).toList();

    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({'actions': filtered}));
  }

  Future<void> _handlePostEpisodeActions(
    HttpRequest request,
    HttpResponse response,
  ) async {
    final content = await utf8.decoder.bind(request).join();
    final dynamic body = jsonDecode(content);
    final List rawList = body is List ? body : (body['actions'] as List? ?? []);

    for (final item in rawList) {
      final action = GPodderAction.fromMap(Map<String, dynamic>.from(item as Map));
      _episodeActions.add(action);
    }

    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({'status': 'ok'}));
  }
}

class _SubscriptionChange {
  final String url;
  final String action;
  final int timestamp;

  _SubscriptionChange(this.url, this.action, this.timestamp);
}
