import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/main.dart';

void main() {
  testWidgets('Podcast Merlin App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PodcastMerlinApp(),
      ),
    );
    expect(find.byType(PodcastMerlinApp), findsOneWidget);
  });
}
