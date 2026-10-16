import '../data/ledger.dart';
import '../data/settings_store.dart';
import '../ingest/ingest.dart';
import 'sheet_layout.dart';
import 'sheets_gateway.dart';

enum SyncResult { ok, notConnected, authRequired, sheetMissing, failed }

/// One-way sync: the phone is the source of truth and every sync rewrites the
/// transactions tab with the full current ledger, so retries never duplicate.
class SyncService {
  final Ledger ledger;
  final SettingsStore settings;
  final Ingest ingest;
  final SheetsGateway Function() gateway;
  final DateTime Function() _clock;

  Future<SyncResult>? _running;

  SyncService({
    required this.ledger,
    required this.settings,
    required this.ingest,
    required this.gateway,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Creates the spreadsheet unless one is already linked (or [recreate]).
  Future<void> connect({bool recreate = false}) async {
    if (!recreate && await settings.get(SettingKeys.spreadsheetId) != null) {
      return;
    }
    final id = await gateway().createSpreadsheet(
      title: 'MoneyLens',
      summary: summaryRows(),
    );
    await settings.set(SettingKeys.spreadsheetId, id);
    await settings.set(SettingKeys.lastSyncError, null);
  }

  /// Sheets from an earlier install worth offering for restore: only while
  /// nothing is linked and the ledger is empty, so a restore never has local
  /// data to lose.
  Future<List<SheetFile>> restorable() async {
    if (await settings.get(SettingKeys.spreadsheetId) != null) return [];
    if (!await ledger.isEmpty()) return [];
    return gateway().findSpreadsheets();
  }

  /// Loads [spreadsheetId] into the empty ledger, then links it. Linking
  /// comes last on purpose: sync rewrites the whole tab, so linking first and
  /// syncing an empty ledger would wipe the very data being restored.
  /// Returns how many transactions came back.
  Future<int> restore(String spreadsheetId) async {
    if (!await ledger.isEmpty()) {
      throw StateError('restore needs an empty ledger');
    }
    final txns = parseTransactionRows(
      await gateway().readTransactions(spreadsheetId),
    );
    final restored = await ledger.restore(txns);
    await settings.set(SettingKeys.spreadsheetId, spreadsheetId);
    await settings.set(SettingKeys.lastSyncError, null);
    return restored;
  }

  /// Concurrent calls share one pass.
  Future<SyncResult> sync() =>
      _running ??= _sync().whenComplete(() => _running = null);

  Future<SyncResult> _sync() async {
    try {
      await ingest.run();
    } catch (_) {
      // New notifications stay in capture.db and are retried next time.
      return _fail(SyncResult.failed, 'ingest_failed');
    }
    final id = await settings.get(SettingKeys.spreadsheetId);
    if (id == null) return SyncResult.notConnected;
    try {
      await gateway().replaceTransactions(
        id,
        transactionRows(await ledger.all()),
      );
    } on AuthRequired {
      return _fail(SyncResult.authRequired, 'auth_required');
    } on SheetMissing {
      return _fail(SyncResult.sheetMissing, 'sheet_missing');
    } catch (e) {
      // Only the error type: messages may echo request content.
      return _fail(SyncResult.failed, 'failed: ${e.runtimeType}');
    }
    await settings.set(
      SettingKeys.lastSyncAt,
      _clock().toUtc().toIso8601String(),
    );
    await settings.set(
      SettingKeys.lastSyncedChangeAt,
      (await ledger.latestUpdate())?.toIso8601String(),
    );
    await settings.set(SettingKeys.lastSyncError, null);
    return SyncResult.ok;
  }

  Future<SyncResult> _fail(SyncResult result, String code) async {
    await settings.set(SettingKeys.lastSyncError, code);
    return result;
  }
}
