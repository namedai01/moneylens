import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schema of `capture.db`. Must match `CaptureDb.kt` exactly — Kotlin owns it.
const captureDbSchema = [
  '''
CREATE TABLE raw_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL DEFAULT 'android_notif',
  package_name TEXT NOT NULL,
  title TEXT, text TEXT, big_text TEXT,
  posted_at INTEGER NOT NULL,
  received_at INTEGER NOT NULL,
  dedup_hash TEXT NOT NULL UNIQUE
)''',
  'CREATE TABLE listener_state (key TEXT PRIMARY KEY, value INTEGER NOT NULL)',
];

var _hash = 0;

/// A `raw_events` row; only [id]-independent fields need values.
Map<String, Object?> rawRow({
  String packageName = 'com.VCB',
  String? title = 'VCB',
  String? text,
  String? bigText,
  required DateTime postedAt,
}) => {
  'package_name': packageName,
  'title': title,
  'text': text,
  'big_text': bigText,
  'posted_at': postedAt.millisecondsSinceEpoch,
  'received_at': postedAt.millisecondsSinceEpoch,
  'dedup_hash': 'h${_hash++}',
};

/// Creates `capture.db` in [dir] the way the Kotlin listener would.
Future<String> createCaptureDb(
  String dir,
  List<Map<String, Object?>> rows, {
  Map<String, int> state = const {},
}) async {
  sqfliteFfiInit();
  final path = p.join(dir, 'capture.db');
  final db = await databaseFactoryFfi.openDatabase(path);
  for (final sql in captureDbSchema) {
    await db.execute(sql);
  }
  for (final r in rows) {
    await db.insert('raw_events', r);
  }
  for (final e in state.entries) {
    await db.insert('listener_state', {'key': e.key, 'value': e.value});
  }
  await db.close();
  return path;
}

/// Appends rows to an existing fixture, as the listener does while the app runs.
Future<void> appendRaw(String path, List<Map<String, Object?>> rows) async {
  // A separate writable connection, like Kotlin's, not the cached read-only one.
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  for (final r in rows) {
    await db.insert('raw_events', r);
  }
  await db.close();
}
