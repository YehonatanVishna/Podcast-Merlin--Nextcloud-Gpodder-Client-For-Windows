import 'dart:io';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

void setupFfi() {
  if (Platform.isAndroid) {
    try {
      applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    } catch (_) {}
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    try {
      JustAudioMediaKit.ensureInitialized();
    } catch (_) {}
  }
}
