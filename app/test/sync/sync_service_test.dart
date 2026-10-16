import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/raw_event_source.dart';
import 'package:moneylens/data/ledger.dart';
import 'package:moneylens/data/parse_log.dart';
import 'package:moneylens/data/settings_store.dart';
import 'package:moneylens/ingest/ingest.dart';
import 'package:moneylens/sync/sheet_layout.dart';
import 'package:moneylens/sync/sheets_gateway.dart';
import 'package:moneylens/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/app_db_fixture.dart';
import '../support/capture_db_fixture.dart';
import '../support/fake_sheets_gateway.dart';
import '../support/samples.dart';

void main() {
  late Directory dir;
  late String capturePath;
  late Ledger ledger;
  late SettingsStore settings;
  late FakeSheetsGateway gateway;
  late SyncService sync;
  late RawEventSource source;
  late DateTime now;

  DateTime at(int minute) => DateTime.utc(2026, 10, 16, 3, minute);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync');
    capturePath = await createCaptureDb(dir.path, [
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1', balance: 9000000),
        postedAt: at(1),
      ),
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.2', balance: 7500000),
        postedAt: at(2),
      ),
    ]);
    final db = await memoryAppDb();
    now = DateTime.utc(2026, 10, 16, 6);
    ledger = Ledger(db, clock: () => now);
    settings = SettingsStore(db);
    gateway = FakeSheetsGateway();
    final rules = bundledRules();
    source = await RawEventSource.open(
      capturePath,
      factory: databaseFactoryFfi,
    );
    sync = SyncService(
      ledger: ledger,
      settings: settings,
      ingest: Ingest(
        source: await RawEventSource.open(
          capturePath,
          factory: databaseFactoryFfi,
        ),
        ledger: ledger,
        parseLog: ParseLog(db),
        rules: () => rules,
      ),
      gateway: () => gateway,
      clock: () => now,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  test('not connected skips network', () async {
    expect(await sync.sync(), SyncResult.notConnected);
    expect(gateway.created, isEmpty);
    expect(gateway.replaced, isEmpty);
  });

  test('connect creates spreadsheet once', () async {
    await sync.connect();
    await sync.connect();
    expect(gateway.created, hasLength(1));
    expect(gateway.created.single.title, 'MoneyLens');
    expect(await settings.get(SettingKeys.spreadsheetId), 'sheet-1');
    await sync.connect(recreate: true);
    expect(gateway.created, hasLength(2));
    expect(await settings.get(SettingKeys.spreadsheetId), 'sheet-2');
  });

  test('sync runs ingest first', () async {
    await sync.connect();
    expect(await sync.sync(), SyncResult.ok);
    final rows = gateway.replaced.single.rows;
    expect(rows, hasLength(4));
    expect(rows.skip(2).map((r) => r[0]), ['MBVCB.1', 'MBVCB.2']);
  });

  test('sync writes full current state every time', () async {
    await sync.connect();
    await sync.sync();
    final id1 = (await ledger.all()).first.id;
    now = now.add(const Duration(minutes: 1));
    await ledger.setExcluded(id1, true);
    await sync.sync();

    expect(gateway.replaced, hasLength(2));
    final second = gateway.replaced[1].rows;
    expect(second, hasLength(4));
    expect(second[2][7], true);
    expect(second[3][7], false);
    expect(await settings.get(SettingKeys.lastSyncAt), now.toIso8601String());
    expect(
      await settings.get(SettingKeys.lastSyncedChangeAt),
      (await ledger.latestUpdate())!.toIso8601String(),
    );
  });

  test('auth required is recorded', () async {
    await sync.connect();
    gateway.throwOnNext = AuthRequired();
    expect(await sync.sync(), SyncResult.authRequired);
    expect(await settings.get(SettingKeys.lastSyncError), 'auth_required');
    expect(await settings.get(SettingKeys.lastSyncAt), isNull);
  });

  test('sheet missing is recorded', () async {
    await sync.connect();
    gateway.throwOnNext = SheetMissing();
    expect(await sync.sync(), SyncResult.sheetMissing);
    expect(await settings.get(SettingKeys.lastSyncError), 'sheet_missing');
  });

  test('other errors are recorded without transaction content', () async {
    await sync.connect();
    gateway.throwOnNext = const SocketException('MBVCB.1 leaked?');
    expect(await sync.sync(), SyncResult.failed);
    final err = await settings.get(SettingKeys.lastSyncError);
    expect(err, 'failed: SocketException');
  });

  test('success clears the previous error', () async {
    await sync.connect();
    gateway.throwOnNext = AuthRequired();
    await sync.sync();
    expect(await sync.sync(), SyncResult.ok);
    expect(await settings.get(SettingKeys.lastSyncError), isNull);
  });

  test('concurrent syncs share one pass', () async {
    await sync.connect();
    await Future.wait([sync.sync(), sync.sync()]);
    expect(gateway.replaced, hasLength(1));
  });

  test('ingest failure is recorded, not thrown', () async {
    await sync.connect();
    await source.db.close();
    expect(await sync.sync(), SyncResult.failed);
    expect(await settings.get(SettingKeys.lastSyncError), 'ingest_failed');
    expect(gateway.replaced, isEmpty);
  });

  group('restore', () {
    const old = SheetFile(id: 'old', name: 'MoneyLens');

    /// What an earlier install synced: its two transactions, one hidden.
    Future<List<List<Object?>>> earlierSheet() async {
      await sync.connect();
      await sync.sync();
      await ledger.setExcluded((await ledger.all()).first.id, true);
      await sync.sync();
      return gateway.replaced.last.rows;
    }

    test('offers Sheets only on a fresh, unlinked ledger', () async {
      gateway.files = [old];
      expect(await sync.restorable(), [old]);
      await settings.set(SettingKeys.spreadsheetId, 'linked');
      expect(await sync.restorable(), isEmpty);
      await settings.set(SettingKeys.spreadsheetId, null);
      await ledger.restore(parseTransactionRows(await earlierSheet()));
      await settings.set(SettingKeys.spreadsheetId, null);
      expect(await sync.restorable(), isEmpty);
    });

    test(
      'loads the Sheet, links it, and the next sync rewrites it as is',
      () async {
        final rows = await earlierSheet();
        final fresh = SyncService(
          ledger: Ledger(await memoryAppDb(), clock: () => now),
          settings: SettingsStore(await memoryAppDb()),
          ingest: sync.ingest,
          gateway: () => gateway,
          clock: () => now,
        );
        gateway.tabs['old'] = rows;

        expect(await fresh.restore('old'), 2);
        expect(await fresh.settings.get(SettingKeys.spreadsheetId), 'old');
        final restored = await fresh.ledger.all();
        expect(restored.map((t) => t.ref), ['MBVCB.1', 'MBVCB.2']);
        expect(restored.map((t) => t.excluded), [true, false]);

        // Everything but the local row ids survives the round trip.
        final rewritten = transactionRows(restored);
        List<Object?> withoutId(List<Object?> r) => [...r]..removeAt(10);
        expect(rewritten.skip(2).map(withoutId), rows.skip(2).map(withoutId));
      },
    );

    test('refuses when the ledger has data', () async {
      await sync.connect();
      await sync.sync();
      await settings.set(SettingKeys.spreadsheetId, null);
      gateway.tabs['old'] = transactionRows([]);
      expect(() => sync.restore('old'), throwsStateError);
      expect(await settings.get(SettingKeys.spreadsheetId), isNull);
    });

    test('an unreadable Sheet is not linked', () async {
      gateway.tabs['old'] = [
        ['not ours'],
      ];
      await expectLater(sync.restore('old'), throwsFormatException);
      expect(await settings.get(SettingKeys.spreadsheetId), isNull);
      expect(await ledger.isEmpty(), isTrue);
    });
  });
}
