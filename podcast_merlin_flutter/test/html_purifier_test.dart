import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/utils/html_purifier.dart';

void main() {
  group('HtmlPurifier Tests', () {
    test('removes malicious script tags and inline XSS handlers', () {
      const maliciousHtml = '<p>Hello <script>alert("xss")</script><img src="x" onerror="alert(1)">World</p>';
      final purified = HtmlPurifier.purify(maliciousHtml);
      expect(purified.contains('<script>'), false);
      expect(purified.contains('onerror='), false);
      expect(purified.contains('Hello'), true);
      expect(purified.contains('World'), true);
    });

    test('preserves safe formatting tags like p, b, i, a', () {
      const safeHtml = '<p>This is <b>bold</b> and <i>italic</i> with <a href="https://example.com">link</a>.</p>';
      final purified = HtmlPurifier.purify(safeHtml);
      expect(purified, contains('<b>bold</b>'));
      expect(purified, contains('<i>italic</i>'));
      expect(purified, contains('<a href="https://example.com">link</a>'));
    });

    test('handles empty and plain text inputs cleanly', () {
      expect(HtmlPurifier.purify(''), '');
      expect(HtmlPurifier.purify('Just plain text'), 'Just plain text');
    });
  });
}
