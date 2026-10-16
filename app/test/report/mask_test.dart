import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/report/mask.dart';

const sample =
    'Số dư TK VCB 0011004123456 -1,500,000 VND lúc 16-10-2026 10:24:27. '
    'Số dư 8,500,000 VND. Ref MBVCB.11223344556.TRAN A chuyen tien.CT tu '
    '0011004123456 TRAN A toi 0123456789 NGUYỄN THỊ BÍCH';

void main() {
  final masked = maskSample(sample);

  test('no run of three or more original digits survives', () {
    for (final run in RegExp(r'\d{3,}').allMatches(sample)) {
      expect(masked, isNot(contains(run.group(0))), reason: run.group(0));
    }
  });

  test('keeps separators and digit group lengths', () {
    expect(masked, contains('-9,999,999 VND'));
    expect(masked, contains('Số dư 9,999,999 VND'));
    expect(masked, contains('lúc 99-99-9999 99:99:99.'));
  });

  test('keeps the fixed words rules are written against', () {
    for (final w in ['Số dư TK VCB', 'VND', 'lúc', 'Ref MBVCB.', '.CT tu']) {
      expect(masked, contains(w), reason: w);
    }
  });

  test('masks names, keeps lowercase words', () {
    expect(masked, isNot(contains('TRAN')));
    expect(masked, isNot(contains('NGUYỄN')));
    expect(masked, isNot(contains('BÍCH')));
    expect(masked, isNot(contains(' A ')));
    expect(masked, contains('chuyen tien'));
    expect(masked, contains('XXXX X chuyen tien'));
  });
}
