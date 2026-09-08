import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

String? audioBackendInitError;

void setupFfi() {
  databaseFactory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      indexedDbName: 'podcast_merlin_web_db',
    ),
  );
}

