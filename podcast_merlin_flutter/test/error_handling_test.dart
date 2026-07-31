import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:podcast_merlin_flutter/core/utils/error_formatter.dart';
import 'package:podcast_merlin_flutter/features/podcasts/rss_feed_parser.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';

import 'sync_service_test.dart';

void main() {
  group('AppErrorFormatter Unit Tests', () {
    test('formats Dio connectionTimeout error', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionTimeout,
      );
      final msg = AppErrorFormatter.format(dioErr);
      expect(msg, contains('Connection timed out'));
    });

    test('formats Dio badResponse HTTP 401 error', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 401,
        ),
      );
      final msg = AppErrorFormatter.format(dioErr);
      expect(msg, contains('Authentication failed (401)'));
    });

    test('formats Dio badResponse HTTP 404 error', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 404,
        ),
      );
      final msg = AppErrorFormatter.format(dioErr);
      expect(msg, contains('not found (404)'));
    });

    test('formats generic Exception', () {
      final msg = AppErrorFormatter.format(Exception('Custom error test'));
      expect(msg, equals('Custom error test'));
    });
  });

  group('RssFeedParser Error Handling Tests', () {
    late RssFeedParser parser;

    setUp(() {
      parser = RssFeedParser();
    });

    test('parseFeedFromUrl throws RssParseException for empty URL', () async {
      expect(
        () => parser.parseFeedFromUrl(''),
        throwsA(isA<RssParseException>().having(
          (e) => e.message,
          'message',
          contains('URL cannot be empty'),
        )),
      );
    });

    test('parseFeedFromUrl throws RssParseException for invalid URI scheme', () async {
      expect(
        () => parser.parseFeedFromUrl('ftp://example.com/feed.xml'),
        throwsA(isA<RssParseException>().having(
          (e) => e.message,
          'message',
          contains('Invalid feed URL scheme'),
        )),
      );
    });

    test('parseFeedXml throws RssParseException for empty XML string', () {
      expect(
        () => parser.parseFeedXml('', 'https://example.com/feed.xml'),
        throwsA(isA<RssParseException>().having(
          (e) => e.message,
          'message',
          contains('content is empty'),
        )),
      );
    });

    test('parseFeedXml throws RssParseException for malformed XML structure', () {
      expect(
        () => parser.parseFeedXml('<rss><channel><title>Unclosed tag', 'https://example.com/feed.xml'),
        throwsA(isA<RssParseException>().having(
          (e) => e.message,
          'message',
          contains('Malformed XML'),
        )),
      );
    });

    test('parseFeedXml throws RssParseException when channel/feed root missing', () {
      expect(
        () => parser.parseFeedXml('<?xml version="1.0"?><invalidRoot></invalidRoot>', 'https://example.com/feed.xml'),
        throwsA(isA<RssParseException>().having(
          (e) => e.message,
          'message',
          contains('missing channel or feed root'),
        )),
      );
    });
  });

  group('GPodderApiClient Error Handling Tests', () {
    late GPodderApiClient apiClient;

    setUp(() {
      apiClient = GPodderApiClient();
    });

    test('testConnectionDetailed returns error when serverUrl is empty', () async {
      final result = await apiClient.testConnectionDetailed(
        serverUrl: '',
        username: 'user',
        password: 'pass',
      );
      expect(result, contains('Server URL cannot be empty'));
    });

    test('testConnectionDetailed returns error when credentials empty', () async {
      final result = await apiClient.testConnectionDetailed(
        serverUrl: 'https://example.com',
        username: '',
        password: '',
      );
      expect(result, contains('Username and password cannot be empty'));
    });
  });

  group('SyncService & SyncStatusNotifier Error Propagation Tests', () {
    test('performFullSync sets lastError and returns false when credentials missing', () async {
      final emptyStorage = TestSecureStorageService();
      final syncService = SyncService(
        apiClient: TestGPodderApiClient(),
        storage: emptyStorage,
      );

      final result = await syncService.performFullSync();
      expect(result, isFalse);
      expect(syncService.lastError, contains('Server credentials not configured'));
    });

    test('SyncStatusNotifier captures and stores detailed error message in state', () async {
      final emptyStorage = TestSecureStorageService();
      final syncService = SyncService(
        apiClient: TestGPodderApiClient(),
        storage: emptyStorage,
      );
      final notifier = SyncStatusNotifier(syncService);

      final success = await notifier.performFullSync();
      expect(success, isFalse);
      expect(notifier.state.error, contains('Server credentials not configured'));

      // Test clearError
      notifier.clearError();
      expect(notifier.state.error, isNull);
    });
  });
}
