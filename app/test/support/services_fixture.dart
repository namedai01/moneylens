import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneylens/app_services.dart';
import 'package:moneylens/sync/sheets_gateway.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'capture_db_fixture.dart';

/// Full service graph over temp files, as the app wires it, without network.
Future<AppServices> testServices(
  Directory dir,
  List<Map<String, Object?>> raws, {
  SheetsGateway Function()? gateway,
  http.Client? client,
}) async {
  final capture = await createCaptureDb(dir.path, raws);
  final s = await AppServices.assemble(
    capturePath: capture,
    appDbPath: p.join(dir.path, 'moneylens.db'),
    rulesCache: File(p.join(dir.path, 'rules-cache.json')),
    loadBundled: () => File('assets/parser-rules.json').readAsString(),
    client: client ?? MockClient((_) async => http.Response('', 404)),
    factory: databaseFactoryFfi,
    gateway: gateway,
  );
  await s.rules.load();
  return s;
}
