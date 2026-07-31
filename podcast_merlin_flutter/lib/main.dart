import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/database/ffi_init.dart';
import 'core/providers/app_providers.dart';
import 'features/player/audio_player_service.dart';
import 'features/ui/views/main_shell.dart';

class GoBackIntent extends Intent {
  const GoBackIntent();
}

class GoForwardIntent extends Intent {
  const GoForwardIntent();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request notification permission on Android 13+ for native notification shade controls
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  // Platform-safe FFI setup (noop on Web, sqflite_ffi on Desktop/Mobile)
  setupFfi();

  // Initialize audio_service so the handler is registered with the platform's
  // media session (Android notification shade, lock-screen controls, etc.)
  final audioHandler = await AudioService.init(
    builder: () => MerlinAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.podcastmerlin.audio',
      androidNotificationChannelName: 'Podcast Merlin Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationClickStartsActivity: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const PodcastMerlinApp(),
    ),
  );
}

class PodcastMerlinApp extends StatelessWidget {
  const PodcastMerlinApp({super.key});

  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();

  static bool handleGoBack() {
    final navState = rootNavigatorKey.currentState;
    if (navState != null && navState.canPop()) {
      navState.pop();
      return true;
    }
    return mainShellKey.currentState?.goBack() ?? false;
  }

  static bool handleGoForward() {
    return mainShellKey.currentState?.goForward() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Podcast Merlin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD0BCFF),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): const GoBackIntent(),
            const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): const GoForwardIntent(),
            const SingleActivator(LogicalKeyboardKey.browserBack): const GoBackIntent(),
            const SingleActivator(LogicalKeyboardKey.browserForward): const GoForwardIntent(),
            const SingleActivator(LogicalKeyboardKey.navigatePrevious): const GoBackIntent(),
            const SingleActivator(LogicalKeyboardKey.navigateNext): const GoForwardIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              GoBackIntent: CallbackAction<GoBackIntent>(
                onInvoke: (_) => handleGoBack(),
              ),
              GoForwardIntent: CallbackAction<GoForwardIntent>(
                onInvoke: (_) => handleGoForward(),
              ),
            },
            child: Focus(
              autofocus: true,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (PointerDownEvent event) {
                  if ((event.buttons & kBackMouseButton) != 0) {
                    handleGoBack();
                  } else if ((event.buttons & kForwardMouseButton) != 0) {
                    handleGoForward();
                  }
                },
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: MainShell(key: mainShellKey),
    );
  }
}
