import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/sync/sync_status.dart';

void main() {
  test('error codes become Vietnamese hints', () {
    expect(describeSyncError(null), isNull);
    expect(
      describeSyncError('auth_required'),
      contains('đăng nhập lại Google'),
    );
    expect(
      describeSyncError('sheet_missing'),
      contains('Không tìm thấy Sheet'),
    );
    expect(describeSyncError('failed: SocketException'), contains('thử lại'));
    expect(describeSyncError('ingest_failed'), contains('Không đọc được'));
  });

  test('sheet url points at the spreadsheet', () {
    expect(
      sheetUrl('abc').toString(),
      'https://docs.google.com/spreadsheets/d/abc',
    );
  });
}
