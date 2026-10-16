import 'package:sqflite/sqflite.dart';

import 'raw_event.dart';

/// Read-only view of `capture.db`, which the Kotlin listener owns and writes.
class RawEventSource {
  final Database db;

  RawEventSource(this.db);

  static Future<RawEventSource> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    return RawEventSource(
      await f.openDatabase(path, options: OpenDatabaseOptions(readOnly: true)),
    );
  }

  Future<List<RawEvent>> after(int afterId, {int limit = 500}) async {
    final rows = await db.query(
      'raw_events',
      where: 'id > ?',
      whereArgs: [afterId],
      orderBy: 'id',
      limit: limit,
    );
    return rows.map(RawEvent.fromRow).toList();
  }

  Future<List<RawEvent>> byIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final rows = await db.query(
      'raw_events',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
      orderBy: 'id',
    );
    return rows.map(RawEvent.fromRow).toList();
  }

  Future<List<RawEvent>> recent({int limit = 20}) async {
    final rows = await db.query(
      'raw_events',
      orderBy: 'posted_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(RawEvent.fromRow).toList();
  }

  Future<DateTime?> listenerConnectedAt() => _state('connected_at');

  Future<DateTime?> lastVcbAt() => _state('last_vcb_at');

  Future<DateTime?> _state(String key) async {
    final rows = await db.query(
      'listener_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      rows.first['value']! as int,
      isUtc: true,
    );
  }
}
