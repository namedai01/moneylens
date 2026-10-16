import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/format.dart';

void main() {
  test('formatVnd groups thousands with dots', () {
    expect(formatVnd(1500000), '1.500.000 ₫');
    expect(formatVnd(0), '0 ₫');
    expect(formatVnd(999), '999 ₫');
  });

  test('formatVnd signed shows plus and minus', () {
    expect(formatVnd(1500000, signed: true), '+1.500.000 ₫');
    expect(formatVnd(-300000, signed: true), '−300.000 ₫');
    expect(formatVnd(-300000), '−300.000 ₫');
  });

  test('formatVnTime uses Vietnam time', () {
    expect(formatVnTime(DateTime.utc(2026, 10, 16, 17, 5)), '17/10 00:05');
  });
}
