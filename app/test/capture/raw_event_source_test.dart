import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/raw_event_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/capture_db_fixture.dart';

void main() {
  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('raw_source');
  });

  tearDown(() => dir.delete(recursive: true));

  DateTime at(int minute) => DateTime.utc(2026, 10, 16, 3, minute);

  Future<RawEventSource> open(
    List<Map<String, Object?>> rows, {
    Map<String, int> state = const {},
  }) async {
    final path = await createCaptureDb(dir.path, rows, state: state);
    return RawEventSource.open(path, factory: databaseFactoryFfi);
  }

  test('after returns rows with id greater than cursor, ascending', () async {
    final s = await open([
      for (var i = 1; i <= 3; i++) rawRow(text: 't$i', postedAt: at(i)),
    ]);
    expect((await s.after(1)).map((e) => e.id), [2, 3]);
  });

  test('after respects limit', () async {
    final s = await open([
      for (var i = 1; i <= 3; i++) rawRow(text: 't$i', postedAt: at(i)),
    ]);
    expect(await s.after(0, limit: 2), hasLength(2));
  });

  test('recent returns newest posted first', () async {
    final s = await open([
      rawRow(text: 'a', postedAt: at(1)),
      rawRow(text: 'c', postedAt: at(3)),
      rawRow(text: 'b', postedAt: at(2)),
    ]);
    expect((await s.recent(limit: 2)).map((e) => e.text), ['c', 'b']);
  });

  test('byIds returns only the requested rows', () async {
    final s = await open([
      for (var i = 1; i <= 3; i++) rawRow(text: 't$i', postedAt: at(i)),
    ]);
    expect((await s.byIds([1, 3])).map((e) => e.id), [1, 3]);
    expect(await s.byIds([]), isEmpty);
  });

  test('body prefers bigText', () async {
    final s = await open([
      rawRow(text: 't', bigText: '', postedAt: at(1)),
      rawRow(text: 't', bigText: 'big', postedAt: at(2)),
    ]);
    final rows = await s.after(0);
    expect(rows[0].body, 't');
    expect(rows[1].body, 'big');
    expect(rows[1].postedAt, at(2));
    expect(rows[1].postedAt.isUtc, isTrue);
  });

  test('listener state reads epoch ms as UTC', () async {
    final s = await open(
      [],
      state: {
        'connected_at': DateTime.utc(2026, 10, 16, 3).millisecondsSinceEpoch,
      },
    );
    expect(await s.listenerConnectedAt(), DateTime.utc(2026, 10, 16, 3));
    expect(await s.lastVcbAt(), isNull);
  });

  test('open is read-only', () async {
    final s = await open([]);
    expect(
      () => s.db.insert('listener_state', {'key': 'x', 'value': 1}),
      throwsA(isA<DatabaseException>()),
    );
  });
}
