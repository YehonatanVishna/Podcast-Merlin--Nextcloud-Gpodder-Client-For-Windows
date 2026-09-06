import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> getDatabasePath(String fileName) async {
  try {
    final appSupportDir = await getApplicationSupportDirectory();
    return p.join(appSupportDir.path, fileName);
  } catch (_) {
    final userHome = Platform.isLinux
        ? (Platform.environment['HOME'] ?? '.')
        : '.';
    final persistentDir = Directory(p.join(userHome, '.config', 'podcast_merlin'));
    if (!await persistentDir.exists()) {
      await persistentDir.create(recursive: true);
    }
    return p.join(persistentDir.path, fileName);
  }
}
