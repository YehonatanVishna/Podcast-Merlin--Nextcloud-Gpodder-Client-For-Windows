import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/services/image_cache_service.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/cached_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Image Cache Widget & Service Tests', () {
    testWidgets('AppCachedImage renders fallback widget when imageUrl is empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCachedImage(
              imageUrl: '',
              width: 50,
              height: 50,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.podcasts), findsOneWidget);
    });

    testWidgets('AppCachedImage renders custom errorWidget on invalid URL', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCachedImage(
              imageUrl: 'invalid_url',
              width: 50,
              height: 50,
              errorWidget: Text('Custom Fallback'),
            ),
          ),
        ),
      );

      expect(find.text('Custom Fallback'), findsOneWidget);
    });

    test('ImageCacheService precacheImageUrl handles empty or invalid strings gracefully', () async {
      await ImageCacheService.precacheImageUrl('');
      await ImageCacheService.precacheImageUrl('  ');
      await ImageCacheService.precacheImageUrl(null);
      // Should complete without throwing exceptions
    });

    test('ImageCacheService precacheBatch handles list of image URLs gracefully', () async {
      await ImageCacheService.precacheBatch([
        '',
        '   ',
        null,
      ]);
      // Should complete without throwing exceptions
    });
  });
}
