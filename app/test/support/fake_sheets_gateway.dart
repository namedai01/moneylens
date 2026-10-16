import 'package:moneylens/sync/sheets_gateway.dart';

class FakeSheetsGateway implements SheetsGateway {
  final created = <({String title, List<List<Object?>> summary})>[];
  final replaced = <({String id, List<List<Object?>> rows})>[];

  /// What [findSpreadsheets] returns.
  var files = <SheetFile>[];

  /// Transactions tab per spreadsheet id, for [readTransactions].
  final tabs = <String, List<List<Object?>>>{};

  /// Thrown by the next call, then cleared.
  Object? throwOnNext;

  void _maybeThrow() {
    final e = throwOnNext;
    throwOnNext = null;
    if (e != null) throw e;
  }

  @override
  Future<String> createSpreadsheet({
    required String title,
    required List<List<Object?>> summary,
  }) async {
    _maybeThrow();
    created.add((title: title, summary: summary));
    return 'sheet-${created.length}';
  }

  @override
  Future<void> replaceTransactions(
    String spreadsheetId,
    List<List<Object?>> rows,
  ) async {
    _maybeThrow();
    replaced.add((id: spreadsheetId, rows: rows));
  }

  @override
  Future<List<SheetFile>> findSpreadsheets() async {
    _maybeThrow();
    return files;
  }

  @override
  Future<List<List<Object?>>> readTransactions(String spreadsheetId) async {
    _maybeThrow();
    final tab = tabs[spreadsheetId];
    if (tab == null) throw SheetMissing();
    return tab;
  }
}
