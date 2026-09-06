import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('Mouse forward and backward buttons trigger navigation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final audioHandler = MerlinAudioHandler();
    addTearDown(audioHandler.stop);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(audioHandler),
        ],
        child: const PodcastMerlinApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Verify initial view is Catalog tab (index 0)
    expect(PodcastMerlinApp.mainShellKey.currentState!.selectedIndex, 0);

    // Switch to Episodes view (tab index 1)
    PodcastMerlinApp.mainShellKey.currentState!.navigateTo(1);
    await tester.pump(const Duration(milliseconds: 500));

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
    await tester.pump(const Duration(milliseconds: 500));

    // Verify returned to Catalog view (index 0)
    expect(PodcastMerlinApp.mainShellKey.currentState!.selectedIndex, 0);

    // Simulate Mouse Forward button press using startGesture
    final forwardGesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kForwardMouseButton,
    );
    await forwardGesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify returned forward to Episodes view (index 1)
    expect(PodcastMerlinApp.mainShellKey.currentState!.selectedIndex, 1);
    expect(find.text('All Episodes'), findsOneWidget);
  });

  testWidgets('Mouse back button pops open dialogs first', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final audioHandler = MerlinAudioHandler();
    addTearDown(audioHandler.stop);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(audioHandler),
        ],
        child: const PodcastMerlinApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Open a test dialog over the app shell
    final BuildContext context = PodcastMerlinApp.rootNavigatorKey.currentContext!;
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Subscribe to Podcast Feed'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Subscribe to Podcast Feed'), findsOneWidget);

    // Press mouse back button
    final center = tester.getCenter(find.byType(PodcastMerlinApp));
    final backGesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await backGesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    // Dialog should be popped / closed
    expect(find.text('Subscribe to Podcast Feed'), findsNothing);
  });
}
