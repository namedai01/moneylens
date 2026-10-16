import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/data/txn.dart';
import 'package:moneylens/sync/sheet_layout.dart';

Txn txn({
  required int id,
  required DateTime at,
  int amount = 300000,
  Direction direction = Direction.outgoing,
  bool excluded = false,
}) => Txn(
  id: id,
  accountId: 1,
  accountLast4: '3456',
  rawEventId: id,
  ref: 'MBVCB.$id',
  source: 'android_notif',
  occurredAt: at,
  amount: amount,
  direction: direction,
  balanceAfter: 1000000,
  description: 'cafe',
  excluded: excluded,
  createdAt: at,
  updatedAt: at,
);

void main() {
  test('notice row, header, then data sorted by time', () {
    final rows = transactionRows([
      txn(id: 2, at: DateTime.utc(2026, 10, 16, 5)),
      txn(
        id: 1,
        at: DateTime.utc(2026, 10, 16, 3, 24, 27),
        amount: 50000,
        direction: Direction.incoming,
        excluded: true,
      ),
    ]);
    expect(rows[0], [txNotice]);
    expect(rows[1], txHeader);
    expect(rows[2], [
      'MBVCB.1',
      '2026-10-16T10:24:27+07:00',
      '2026-10',
      'vào',
      50000,
      1000000,
      'cafe',
      true,
      '3456',
      'android_notif',
      1,
    ]);
    expect(rows[3][3], 'ra');
    expect(rows[3][4], -300000);
    expect(rows[3][7], false);
  });

  test('empty ledger still writes notice and header', () {
    expect(transactionRows([]), [
      [txNotice],
      txHeader,
    ]);
  });

  test('summary formulas read the transactions tab', () {
    final s = summaryRows();
    expect(s.first, ['tháng', 'tổng thu', 'tổng chi', 'chênh lệch']);
    final formulas = s.skip(1).expand((r) => r).whereType<String>().join('\n');
    expect(formulas, contains("'$txTabTitle'!C3:C"));
    // SUMIFS does not expand over an array of criteria inside ARRAYFORMULA
    // (every month would show the same total): evaluate per month instead,
    // with exact text match on the month so "2026-10" is never read as a date.
    expect(formulas, isNot(contains('ARRAYFORMULA(IF(A2:A="",,SUMIFS')));
    final income = s[1][1]! as String;
    expect(income, startsWith('=MAP(A2:A,LAMBDA(m,'));
    expect(
      income,
      contains(
        "FILTER('$txTabTitle'!E3:E,'$txTabTitle'!C3:C=m,'$txTabTitle'!H3:H=FALSE,'$txTabTitle'!E3:E>0)",
      ),
    );
    expect(income, contains('IFERROR('));
  });
}
