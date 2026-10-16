import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/raw_event_source.dart';
import 'package:moneylens/data/ledger.dart';
import 'package:moneylens/data/parse_log.dart';
import 'package:moneylens/ingest/ingest.dart';
import 'package:moneylens/parser/parser_rules.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/app_db_fixture.dart';
import '../support/capture_db_fixture.dart';
import '../support/samples.dart';

void main() {
  late Directory dir;
  late Ledger ledger;
  late ParseLog parseLog;
  late ParserRules rules;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ingest');
    final db = await memoryAppDb();
    ledger = Ledger(db);
    parseLog = ParseLog(db);
    rules = bundledRules();
  });

  tearDown(() => dir.delete(recursive: true));

  DateTime at(int minute) => DateTime.utc(2026, 10, 16, 3, minute);

  Future<Ingest> ingestOver(List<Map<String, Object?>> rows) async {
    final path = await createCaptureDb(dir.path, rows);
    return Ingest(
      source: await RawEventSource.open(path, factory: databaseFactoryFfi),
      ledger: ledger,
      parseLog: parseLog,
      rules: () => rules,
    );
  }

  test('parses new raws and advances cursor', () async {
    final ingest = await ingestOver([
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1'),
        postedAt: at(1),
      ),
      rawRow(bigText: otpText, postedAt: at(2)),
      rawRow(bigText: unknownBalanceText, postedAt: at(3)),
    ]);
    final r = await ingest.run();
    expect([r.parsed, r.ignored, r.failed, r.duplicates], [1, 1, 1, 0]);
    expect(await parseLog.maxRawId(), 3);
    final t = (await ledger.all()).single;
    expect(t.rawEventId, 1);
    expect(t.source, 'android_notif');
    expect(t.accountLast4, '3456');
  });

  test('rerun is idempotent', () async {
    final ingest = await ingestOver([
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1'),
        postedAt: at(1),
      ),
    ]);
    await ingest.run();
    final r = await ingest.run();
    expect([r.parsed, r.ignored, r.failed, r.duplicates], [0, 0, 0, 0]);
    expect(await ledger.all(), hasLength(1));
  });

  test('picks up raws written after the first run', () async {
    final path = await createCaptureDb(dir.path, [
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1'),
        postedAt: at(1),
      ),
    ]);
    final ingest = Ingest(
      source: await RawEventSource.open(path, factory: databaseFactoryFfi),
      ledger: ledger,
      parseLog: parseLog,
      rules: () => rules,
    );
    await ingest.run();
    await appendRaw(path, [
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.2', balance: 7000000),
        postedAt: at(5),
      ),
    ]);
    expect((await ingest.run()).parsed, 1);
    expect(await ledger.all(), hasLength(2));
  });

  test('same transaction from two raws counts once', () async {
    final ingest = await ingestOver([
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1'),
        postedAt: at(1),
      ),
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1'),
        postedAt: at(2),
      ),
    ]);
    final r = await ingest.run();
    expect(r.duplicates, 1);
    expect(await ledger.all(), hasLength(1));
  });

  test('reparseFailed uses new rules', () async {
    final ingest = await ingestOver([
      rawRow(
        bigText:
            'Số dư TK VCB 0011004123456 -50.000 VND lúc 16-10-2026 10:24:27. Số dư 950.000 VND. Ref MBVCB.7.cafe',
        postedAt: at(1),
      ),
    ]);
    // v1 expects "," between thousands, so "." fails.
    await ingest.run();
    expect(await parseLog.failedCount(), 1);

    final m =
        jsonDecode(File('assets/parser-rules.json').readAsStringSync())
            as Map<String, dynamic>;
    m['version'] = 2;
    ((m['rules'] as List)[0] as Map)['thousandsSeparator'] = '.';
    rules = ParserRules.tryParse(jsonEncode(m))!;

    final r = await ingest.reparseFailed();
    expect(r.parsed, 1);
    expect(await parseLog.failedCount(), 0);
    expect((await ledger.all()).single.amount, 50000);
  });

  test('concurrent run calls share one pass', () async {
    final ingest = await ingestOver([
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1'),
        postedAt: at(1),
      ),
    ]);
    final reports = await Future.wait([ingest.run(), ingest.run()]);
    expect(identical(reports[0], reports[1]), isTrue);
    expect(await ledger.all(), hasLength(1));
  });
}
