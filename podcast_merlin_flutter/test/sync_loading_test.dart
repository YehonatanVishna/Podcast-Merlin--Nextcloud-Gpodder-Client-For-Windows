import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/models/sync_status.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/podcast_catalog_view.dart';

class FakeSyncService extends SyncService {
  @override
  Future<bool> performFullSync({SyncProgressCallback? onProgress, bool forceFullResync = false}) async {
    onProgress?.call(SyncStage.connectingGpodder, 'Connecting to gPodder...');
    await Future.delayed(const Duration(milliseconds: 50));
    onProgress?.call(SyncStage.fetchingSubscriptions, 'Fetching subscriptions from gPodder...');
    await Future.delayed(const Duration(milliseconds: 50));
    return true;
  }
}

void main() {
  test('SyncStatusNotifier updates state during performFullSync', () async {
    final fakeSync = FakeSyncService();
    final notifier = SyncStatusNotifier(fakeSync);

    expect(notifier.state.isSyncing, false);
    expect(notifier.state.stage, SyncStage.idle);

    final syncFuture = notifier.performFullSync();
    expect(notifier.state.isSyncing, true);
    expect(notifier.state.stage, SyncStage.connectingGpodder);

    await syncFuture;

    expect(notifier.state.isSyncing, false);
    expect(notifier.state.stage, SyncStage.completed);
  });

  testWidgets('PodcastCatalogView displays sync loading indicator when isSyncing is true', (tester) async {
    final fakeSync = FakeSyncService();
    final container = ProviderContainer(
      overrides: [
        syncServiceProvider.overrideWithValue(fakeSync),
      ],
    );

    // Set state to syncing
    container.read(syncStatusNotifierProvider.notifier).state = const SyncStatusState(
      isSyncing: true,
      stage: SyncStage.connectingGpodder,
      currentTask: 'Connecting to gPodder...',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PodcastCatalogView(),
        ),
      ),
    );

    await tester.pump();

    // Verify status banner and progress indicators are rendered
    expect(find.text('Connecting to gPodder...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
