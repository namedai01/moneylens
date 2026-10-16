import 'package:googleapis/sheets/v4.dart';
import 'package:http/http.dart' as http;

import 'sheet_layout.dart';
import 'sheets_gateway.dart';

/// Sheets API v4 with the user's own token. The token comes from
/// [headers] on every request and is never stored or sent anywhere else.
class GoogleSheetsGateway implements SheetsGateway {
  final SheetsApi _api;

  GoogleSheetsGateway(
    Future<Map<String, String>> Function() headers, {
    http.Client? inner,
  }) : _api = SheetsApi(_AuthClient(headers, inner ?? http.Client()));

  static String _range(String tab, [String cell = '']) =>
      "'$tab'${cell.isEmpty ? '' : '!$cell'}";

  @override
  Future<String> createSpreadsheet({
    required String title,
    required List<List<Object?>> summary,
  }) => _guard(() async {
    final created = await _api.spreadsheets.create(
      Spreadsheet(
        properties: SpreadsheetProperties(title: title),
        sheets: [
          Sheet(properties: SheetProperties(title: txTabTitle)),
          Sheet(properties: SheetProperties(title: summaryTabTitle)),
        ],
      ),
    );
    final id = created.spreadsheetId!;
    await _api.spreadsheets.values.update(
      ValueRange(values: summary),
      id,
      _range(summaryTabTitle, 'A1'),
      valueInputOption: 'USER_ENTERED',
    );
    return id;
  });

  @override
  Future<void> replaceTransactions(
    String spreadsheetId,
    List<List<Object?>> rows,
  ) => _guard(() async {
    await _api.spreadsheets.values.clear(
      ClearValuesRequest(),
      spreadsheetId,
      _range(txTabTitle),
    );
    await _api.spreadsheets.values.update(
      ValueRange(values: rows),
      spreadsheetId,
      _range(txTabTitle, 'A1'),
      valueInputOption: 'RAW',
    );
  });

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DetailedApiRequestError catch (e) {
      switch (e.status) {
        case 401 || 403:
          throw AuthRequired();
        case 404:
          throw SheetMissing();
      }
      rethrow;
    }
  }
}

class _AuthClient extends http.BaseClient {
  final Future<Map<String, String>> Function() _headers;
  final http.Client _inner;

  _AuthClient(this._headers, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(await _headers());
    return _inner.send(request);
  }
}
