import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart';
import 'package:http/http.dart' as http;

import 'sheet_layout.dart';
import 'sheets_gateway.dart';

/// Sheets API v4 with the user's own token. The token comes from
/// [headers] on every request and is never stored or sent anywhere else.
class GoogleSheetsGateway implements SheetsGateway {
  final SheetsApi _api;
  final drive.DriveApi _drive;

  GoogleSheetsGateway(
    Future<Map<String, String>> Function() headers, {
    http.Client? inner,
  }) : this._(_AuthClient(headers, inner ?? http.Client()));

  GoogleSheetsGateway._(http.Client client)
    : _api = SheetsApi(client),
      _drive = drive.DriveApi(client);

  static String _range(String tab, [String cell = '']) =>
      "'$tab'${cell.isEmpty ? '' : '!$cell'}";

  @override
  Future<String> createSpreadsheet({
    required String title,
    required List<List<Object?>> summary,
  }) => _guard(() async {
    final created = await _api.spreadsheets.create(
      Spreadsheet(
        // Summary formulas use "," separators; a sheet inheriting a vi_VN
        // locale expects ";" and every formula would be #ERROR!.
        properties: SpreadsheetProperties(
          title: title,
          locale: 'en_US',
          timeZone: 'Asia/Ho_Chi_Minh',
        ),
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

  @override
  Future<List<SheetFile>> findSpreadsheets() => _guard(() async {
    final list = await _drive.files.list(
      q: "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false",
      orderBy: 'modifiedTime desc',
      pageSize: 20,
      $fields: 'files(id,name,modifiedTime)',
    );
    return [
      for (final f in list.files ?? <drive.File>[])
        SheetFile(id: f.id!, name: f.name ?? '', modifiedAt: f.modifiedTime),
    ];
  });

  @override
  Future<List<List<Object?>>> readTransactions(String spreadsheetId) =>
      _guard(() async {
        final range = await _api.spreadsheets.values.get(
          spreadsheetId,
          _range(txTabTitle),
          valueRenderOption: 'UNFORMATTED_VALUE',
        );
        return range.values ?? [];
      });

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DetailedApiRequestError catch (e) {
      switch (e.status) {
        case 401 || 403:
          throw AuthRequired();
        // 400 "Unable to parse range": the tab was renamed or deleted.
        // Recreating the Sheet is the way out, same as a deleted file.
        case 400 || 404:
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
