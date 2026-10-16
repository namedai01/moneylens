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
  accountBank: 'VCB',
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
      'VCB',
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

  group('parseTransactionRows', () {
    test('reads back what transactionRows wrote', () {
      final at = DateTime.utc(2026, 10, 16, 3, 24, 27);
      final rows = transactionRows([
        txn(id: 1, at: at, amount: 50000, direction: Direction.incoming),
        txn(id: 2, at: at.add(const Duration(hours: 1)), excluded: true),
      ]);
      final back = parseTransactionRows(rows);
      expect(back, hasLength(2));
      final first = back[0];
      expect(first.ref, 'MBVCB.1');
      expect(first.occurredAt, at);
      expect(first.occurredAt.isUtc, isTrue);
      expect(first.direction, Direction.incoming);
      expect(first.amount, 50000);
      expect(first.balanceAfter, 1000000);
      expect(first.description, 'cafe');
      expect(first.excluded, isFalse);
      expect(first.bankCode, 'VCB');
      expect(first.accountLast4, '3456');
      expect(first.source, 'android_notif');
      expect(back[1].direction, Direction.outgoing);
      expect(back[1].amount, 300000);
      expect(back[1].excluded, isTrue);
    });

    test('Sheets from before the bank column default to VCB', () {
      final back = parseTransactionRows([
        [txNotice],
        txHeader.take(11).toList(),
        ['MBVCB.9', '2026-10-16T10:00:00+07:00', '2026-10', 'ra', -1000],
      ]);
      expect(back.single.bankCode, legacyBankCode);
      // Trailing empty cells are dropped by the API.
      expect(back.single.balanceAfter, isNull);
      expect(back.single.description, '');
      expect(back.single.accountLast4, isNull);
    });

    test('skips blank rows', () {
      final back = parseTransactionRows([
        [txNotice],
        txHeader,
        [],
        ['', '', ''],
        ['MBVCB.9', '2026-10-16T10:00:00+07:00', '2026-10', 'ra', -1000],
      ]);
      expect(back, hasLength(1));
    });

    test('a broken row stops the restore and names the Sheet row', () {
      const ok = ['MBVCB.1', '2026-10-16T10:00:00+07:00', '2026-10', 'ra', -1];
      Matcher fails(String message) => throwsA(
        isA<FormatException>().having((e) => e.message, 'message', message),
      );
      expect(
        () => parseTransactionRows([
          [txNotice],
          txHeader,
          ok,
          ['MBVCB.2', 'hôm qua', '2026-10', 'ra', -1],
        ]),
        fails('dòng 4, cột "thời gian" không đọc được'),
      );
      expect(
        () => parseTransactionRows([
          [txNotice],
          txHeader,
          ['MBVCB.2', '2026-10-16T10:00:00+07:00', '2026-10', 'ra', '50k'],
        ]),
        fails('dòng 3, cột "số tiền" không đọc được'),
      );
      expect(
        () => parseTransactionRows([
          [txNotice],
          txHeader,
          ['MBVCB.2', '2026-10-16T10:00:00+07:00', '2026-10', 'ra', 0],
        ]),
        throwsFormatException,
      );
    });

    test('rejects a tab that is not ours', () {
      expect(
        () => parseTransactionRows([
          ['a', 'b'],
          ['ngày', 'số tiền'],
        ]),
        throwsFormatException,
      );
      expect(() => parseTransactionRows([]), throwsFormatException);
    });
  });
}
