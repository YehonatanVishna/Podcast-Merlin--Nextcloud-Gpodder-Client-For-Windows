import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/main.dart';

void main() {
  testWidgets('Mouse forward and backward buttons trigger navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PodcastMerlinApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Verify initial view is Catalog tab (index 0)
    expect(PodcastMerlinApp.mainShellKey.currentState!.selectedIndex, 0);

    // Switch to Episodes view (tab index 1)
    PodcastMerlinApp.mainShellKey.currentState!.navigateTo(1);
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Episodes view is shown
    expect(PodcastMerlinApp.mainShellKey.currentState!.selectedIndex, 1);
    expect(find.text('All Episodes'), findsOneWidget);

    // Simulate Mouse Back button press using startGesture
    final center = tester.getCenter(find.byType(PodcastMerlinApp));
    final backGesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await backGesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify returned to Catalog view (index 0)
    expect(PodcastMerlinApp.mainShellKey.currentState!.selectedIndex, 0);

    // Simulate Mouse Forward button press using startGesture
    final forwardGesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kForwardMouseButton,
    );
    await forwardGesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify returned forward to Episodes view (index 1)
    expect(PodcastMerlinApp.mainShellKey.currentState!.selectedIndex, 1);
    expect(find.text('All Episodes'), findsOneWidget);
  });

  testWidgets('Mouse back button pops open dialogs first', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PodcastMerlinApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Open Add Feed dialog
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Subscribe to Podcast Feed'), findsOneWidget);

    // Press mouse back button
    final center = tester.getCenter(find.byType(PodcastMerlinApp));
    final backGesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await backGesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    // Dialog should be popped / closed
    expect(find.text('Subscribe to Podcast Feed'), findsNothing);
  });
}
