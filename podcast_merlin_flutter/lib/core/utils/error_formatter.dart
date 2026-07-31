import 'dart:io';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

class AppErrorFormatter {
  static String format(dynamic error) {
    if (error == null) return 'An unknown error occurred.';

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timed out. Please check your internet connection or server URL.';
        case DioExceptionType.sendTimeout:
          return 'Request timeout sending data to server.';
        case DioExceptionType.receiveTimeout:
          return 'Server took too long to respond (receive timeout).';
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          if (statusCode == 401 || statusCode == 403) {
            return 'Authentication failed ($statusCode): Invalid username or password.';
          } else if (statusCode == 404) {
            return 'Server resource or feed not found (404). Check the URL.';
          } else if (statusCode != null && statusCode >= 500) {
            return 'Server error ($statusCode): Nextcloud/gPodder server is temporarily unavailable.';
          }
          return 'HTTP error ($statusCode): ${error.response?.statusMessage ?? "Bad response"}';
        case DioExceptionType.cancel:
          return 'Request was cancelled.';
        case DioExceptionType.connectionError:
          return 'Failed to connect to server. Check network connection and server URL.';
        case DioExceptionType.badCertificate:
          return 'SSL certificate error: Untrusted or invalid security certificate.';
        default:
          if (error.error is SocketException) {
            return 'Network connection failed: Unable to reach host.';
          }
          return error.message ?? error.toString();
      }
    }

    if (error is XmlParserException) {
      return 'Invalid RSS XML format: ${error.message}';
    }

    if (error is SocketException) {
      return 'Network offline or unreachable host: ${error.message}';
    }

    if (error is FormatException) {
      return 'Format error: ${error.message}';
    }

    final str = error.toString();
    if (str.startsWith('Exception: ')) {
      return str.substring(11);
    }
    return str;
  }
}
