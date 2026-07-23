import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/ffi_init.dart';
import 'features/ui/views/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Platform-safe FFI setup (noop on Web, sqflite_ffi on Desktop/Mobile)
  setupFfi();

  runApp(
    const ProviderScope(
      child: PodcastMerlinApp(),
    ),
  );
}

class PodcastMerlinApp extends StatelessWidget {
  const PodcastMerlinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: const MainShell(),
    );
  }
}
