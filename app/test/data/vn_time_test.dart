import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/data/vn_time.dart';

void main() {
  test('month boundary uses +07:00', () {
    expect(monthKeyOf(DateTime.utc(2026, 10, 31, 16, 30)), '2026-10');
    expect(monthKeyOf(DateTime.utc(2026, 10, 31, 17, 30)), '2026-11');
  });

  test('monthRangeUtc starts at local midnight', () {
    final r = monthRangeUtc('2026-11');
    expect(r.start, DateTime.utc(2026, 10, 31, 17));
    expect(r.end, DateTime.utc(2026, 11, 30, 17));
    expect(monthRangeUtc('2026-12').end, DateTime.utc(2026, 12, 31, 17));
  });

  test('vnIso renders local time with offset', () {
    expect(
      vnIso(DateTime.utc(2026, 10, 16, 3, 24, 27)),
      '2026-10-16T10:24:27+07:00',
    );
  });
}
