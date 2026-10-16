import 'dart:io';

import 'package:moneylens/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fresh `moneylens.db` in its own temp file. (`inMemoryDatabasePath` is a
/// single shared instance in sqflite, so tests would see each other's rows.)
Future<Database> memoryAppDb() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('appdb');
  return openAppDb(
    p.join(dir.path, 'moneylens.db'),
    factory: databaseFactoryFfiNoIsolate,
  );
}
