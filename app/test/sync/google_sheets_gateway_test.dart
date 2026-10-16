import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneylens/sync/google_sheets_gateway.dart';
import 'package:moneylens/sync/sheet_layout.dart';
import 'package:moneylens/sync/sheets_gateway.dart';

void main() {
  final requests = <http.Request>[];
  setUp(requests.clear);

  GoogleSheetsGateway gateway(
    Future<http.Response> Function(http.Request) handler,
  ) => GoogleSheetsGateway(
    () async => {'Authorization': 'Bearer test-token'},
    inner: MockClient((req) {
      requests.add(req);
      return handler(req);
    }),
  );

  http.Response ok(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  http.Response error(int code) => http.Response(
    jsonEncode({
      'error': {'code': code, 'message': 'x'},
    }),
    code,
    headers: {'content-type': 'application/json'},
  );

  test('replaceTransactions clears then writes raw values from A1', () async {
    await gateway((_) async => ok({})).replaceTransactions('sid', [
      ['a', 1, true],
    ]);
    expect(requests, hasLength(2));
    final clear = requests[0];
    expect(clear.method, 'POST');
    expect(
      Uri.decodeComponent(clear.url.path),
      endsWith("/spreadsheets/sid/values/'$txTabTitle':clear"),
    );
    final put = requests[1];
    expect(put.method, 'PUT');
    expect(
      Uri.decodeComponent(put.url.path),
      endsWith("/spreadsheets/sid/values/'$txTabTitle'!A1"),
    );
    expect(put.url.queryParameters['valueInputOption'], 'RAW');
    expect((jsonDecode(put.body) as Map)['values'], [
      ['a', 1, true],
    ]);
  });

  test('createSpreadsheet makes both tabs and writes the summary', () async {
    final id =
        await gateway((req) async {
          if (req.method == 'POST' &&
              req.url.path.endsWith('/v4/spreadsheets')) {
            return ok({'spreadsheetId': 'new-id'});
          }
          return ok({});
        }).createSpreadsheet(
          title: 'MoneyLens',
          summary: [
            ['tháng'],
          ],
        );
    expect(id, 'new-id');
    final create = jsonDecode(requests[0].body) as Map<String, dynamic>;
    expect(create['properties']['title'], 'MoneyLens');
    // Formulas use "," separators: a vi_VN sheet would expect ";" and show
    // #ERROR! everywhere, so pin the locale instead of inheriting the user's.
    expect(create['properties']['locale'], 'en_US');
    expect(create['properties']['timeZone'], 'Asia/Ho_Chi_Minh');
    expect((create['sheets'] as List).map((s) => s['properties']['title']), [
      txTabTitle,
      summaryTabTitle,
    ]);
    final put = requests[1];
    expect(
      Uri.decodeComponent(put.url.path),
      endsWith("/spreadsheets/new-id/values/'$summaryTabTitle'!A1"),
    );
    expect(put.url.queryParameters['valueInputOption'], 'USER_ENTERED');
  });

  test('401 and 403 mean sign in again', () async {
    expect(
      () => gateway((_) async => error(401)).replaceTransactions('sid', []),
      throwsA(isA<AuthRequired>()),
    );
    expect(
      () => gateway((_) async => error(403)).replaceTransactions('sid', []),
      throwsA(isA<AuthRequired>()),
    );
  });

  test('400 on the tab range means the tab was renamed or deleted', () async {
    expect(
      () => gateway((_) async => error(400)).replaceTransactions('sid', []),
      throwsA(isA<SheetMissing>()),
    );
  });

  test('404 means the sheet is gone', () async {
    expect(
      () => gateway((_) async => error(404)).replaceTransactions('sid', []),
      throwsA(isA<SheetMissing>()),
    );
  });

  test('every request goes to Sheets with the on-device token', () async {
    await gateway((_) async => ok({})).replaceTransactions('sid', []);
    for (final r in requests) {
      expect(r.url.host, 'sheets.googleapis.com');
      expect(r.headers['Authorization'], 'Bearer test-token');
    }
  });

  test('missing token surfaces as AuthRequired', () async {
    final g = GoogleSheetsGateway(
      () async => throw AuthRequired(),
      inner: MockClient((_) async => ok({})),
    );
    expect(
      () => g.replaceTransactions('sid', []),
      throwsA(isA<AuthRequired>()),
    );
  });
}
