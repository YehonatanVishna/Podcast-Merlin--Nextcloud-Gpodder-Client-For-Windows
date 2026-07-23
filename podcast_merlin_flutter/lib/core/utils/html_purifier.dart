import 'package:sanitize_html/sanitize_html.dart';

class HtmlPurifier {
  /// Purifies an HTML string to prevent XSS attacks while keeping safe HTML markup.
  static String purify(String rawHtml) {
    if (rawHtml.isEmpty) return '';
    try {
      return sanitizeHtml(rawHtml);
    } catch (_) {
      return rawHtml.replaceAll(RegExp(r'<[^>]*>'), '');
    }
  }
}
