import 'package:sqflite/sqflite.dart';

/// What happened to each raw notification; a raw without a row is unprocessed.
class ParseLog {
  final Database db;

  ParseLog(this.db);

  /// Highest raw id processed so far, the ingest cursor.
  Future<int> maxRawId() async {
    final rows = await db.rawQuery(
      'SELECT MAX(raw_event_id) AS m FROM raw_parse',
    );
    return rows.first['m'] as int? ?? 0;
  }

  Future<void> record(
    int rawId,
    String status, {
    String? error,
    required int rulesVersion,
  }) => db.insert('raw_parse', {
    'raw_event_id': rawId,
    'parse_status': status,
    'parse_error': error,
    'rules_version': rulesVersion,
    'parsed_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<int>> failedIds() async {
    final rows = await db.query(
      'raw_parse',
      columns: ['raw_event_id'],
      where: "parse_status = 'failed'",
      orderBy: 'raw_event_id',
    );
    return [for (final r in rows) r['raw_event_id']! as int];
  }

  Future<int> failedCount() async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM raw_parse WHERE parse_status = 'failed'",
    );
    return rows.first['c']! as int;
  }
}
