import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'auth/google_auth.dart';
import 'capture/listener.dart';
import 'capture/raw_event_source.dart';
import 'data/app_db.dart';
import 'data/ledger.dart';
import 'data/parse_log.dart';
import 'data/settings_store.dart';
import 'ingest/ingest.dart';
import 'parser/rules_repository.dart';
import 'sync/google_sheets_gateway.dart';
import 'sync/sheets_gateway.dart';
import 'sync/sync_service.dart';

/// Every long-lived object of the app, wired once. Used by the UI and by the
/// background sync job.
class AppServices {
  final RawEventSource source;
  final Ledger ledger;
  final ParseLog parseLog;
  final SettingsStore settings;
  final RulesRepository rules;
  final Ingest ingest;
  final SyncService sync;

  /// Null in tests and wherever Google sign-in is unavailable.
  final GoogleAuth? auth;

  AppServices._({
    required this.source,
    required this.ledger,
    required this.parseLog,
    required this.settings,
    required this.rules,
    required this.ingest,
    required this.sync,
    this.auth,
  });

  /// Production wiring on the phone.
  static Future<AppServices> open() async {
    final support = await getApplicationSupportDirectory();
    final auth = GoogleAuth();
    final gateway = GoogleSheetsGateway(() => auth.headers(interactive: false));
    return assemble(
      capturePath: await captureDbPath(),
      appDbPath: p.join(await getDatabasesPath(), 'moneylens.db'),
      rulesCache: File(p.join(support.path, 'parser-rules.json')),
      loadBundled: () => rootBundle.loadString('assets/parser-rules.json'),
      client: http.Client(),
      gateway: () => gateway,
      auth: auth,
    );
  }

  static Future<AppServices> assemble({
    required String capturePath,
    required String appDbPath,
    required File rulesCache,
    required Future<String> Function() loadBundled,
    required http.Client client,
    DatabaseFactory? factory,
    SheetsGateway Function()? gateway,
    GoogleAuth? auth,
  }) async {
    final db = await openAppDb(appDbPath, factory: factory);
    final source = await RawEventSource.open(capturePath, factory: factory);
    final ledger = Ledger(db);
    final parseLog = ParseLog(db);
    final settings = SettingsStore(db);
    final rules = RulesRepository(
      loadBundled: loadBundled,
      cacheFile: rulesCache,
      client: client,
    );
    final ingest = Ingest(
      source: source,
      ledger: ledger,
      parseLog: parseLog,
      rules: () => rules.current,
    );
    return AppServices._(
      source: source,
      ledger: ledger,
      parseLog: parseLog,
      settings: settings,
      rules: rules,
      ingest: ingest,
      sync: SyncService(
        ledger: ledger,
        settings: settings,
        ingest: ingest,
        gateway: gateway ?? () => const _NotSignedIn(),
      ),
      auth: auth,
    );
  }
}

/// Without a gateway (tests), every Sheets call asks for sign-in.
class _NotSignedIn implements SheetsGateway {
  const _NotSignedIn();

  @override
  Future<String> createSpreadsheet({
    required String title,
    required List<List<Object?>> summary,
  }) => throw AuthRequired();

  @override
  Future<void> replaceTransactions(String id, List<List<Object?>> rows) =>
      throw AuthRequired();
}
