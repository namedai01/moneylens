import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/data/ledger.dart';
import 'package:moneylens/data/txn.dart';

import '../support/app_db_fixture.dart';

void main() {
  late Ledger ledger;
  late DateTime now;
  late int acc;

  setUp(() async {
    now = DateTime.utc(2026, 10, 16, 5);
    ledger = Ledger(await memoryAppDb(), clock: () => now);
    acc = await ledger.accountIdFor(bankCode: 'VCB', last4: '1234');
  });

  NewTxn tx({
    String? ref,
    required DateTime at,
    int amount = 100000,
    Direction direction = Direction.outgoing,
    int? balance,
  }) => NewTxn(
    accountId: acc,
    rawEventId: null,
    ref: ref,
    source: 'android_notif',
    occurredAt: at,
    amount: amount,
    direction: direction,
    balanceAfter: balance,
    description: 'test',
  );

  final oct = DateTime.utc(2026, 10, 10, 3);

  test('same ref twice keeps one', () async {
    expect(await ledger.insertTxn(tx(ref: 'MBVCB.1', at: oct)), isTrue);
    expect(
      await ledger.insertTxn(
        tx(ref: 'MBVCB.1', at: oct.add(const Duration(seconds: 5))),
      ),
      isFalse,
    );
    expect(await ledger.all(), hasLength(1));
  });

  test('no ref, no balance keeps both', () async {
    expect(await ledger.insertTxn(tx(at: oct)), isTrue);
    expect(await ledger.insertTxn(tx(at: oct)), isTrue);
  });

  test('no ref, same balance dedups', () async {
    expect(await ledger.insertTxn(tx(at: oct, balance: 900000)), isTrue);
    expect(await ledger.insertTxn(tx(at: oct, balance: 900000)), isFalse);
  });

  test('summary skips excluded', () async {
    await ledger.insertTxn(
      tx(ref: 'a', at: oct, amount: 1000000, direction: Direction.incoming),
    );
    await ledger.insertTxn(tx(ref: 'b', at: oct, amount: 300000));
    await ledger.insertTxn(tx(ref: 'c', at: oct, amount: 200000));
    final c = (await ledger.all()).firstWhere((t) => t.ref == 'c');
    await ledger.setExcluded(c.id, true);
    final s = await ledger.monthSummary('2026-10');
    expect(s.income, 1000000);
    expect(s.expense, 300000);
    expect(s.net, 700000);
  });

  test('monthTxns uses Vietnam month and joins account', () async {
    await ledger.insertTxn(
      tx(ref: 'late-oct', at: DateTime.utc(2026, 10, 31, 16, 30)),
    );
    await ledger.insertTxn(
      tx(ref: 'early-nov', at: DateTime.utc(2026, 10, 31, 17, 30)),
    );
    final octTx = await ledger.monthTxns('2026-10');
    expect(octTx.map((t) => t.ref), ['late-oct']);
    expect(octTx.single.accountLast4, '1234');
    expect((await ledger.monthTxns('2026-11')).map((t) => t.ref), [
      'early-nov',
    ]);
  });

  test('setExcluded bumps updatedAt', () async {
    await ledger.insertTxn(tx(ref: 'a', at: oct));
    final before = await ledger.latestUpdate();
    now = now.add(const Duration(seconds: 1));
    await ledger.setExcluded((await ledger.all()).single.id, true);
    expect(await ledger.latestUpdate(), isNot(before));
    expect(await ledger.changedSince(before), 1);
    expect(await ledger.changedSince(null), 1);
    expect((await ledger.all()).single.excluded, isTrue);
  });

  test('lastMonths fills empty months with zeros', () async {
    await ledger.insertTxn(
      tx(ref: 'aug', at: DateTime.utc(2026, 8, 5), amount: 50000),
    );
    await ledger.insertTxn(
      tx(ref: 'oct', at: oct, amount: 70000, direction: Direction.incoming),
    );
    final months = await ledger.lastMonths(3, now: DateTime.utc(2026, 10, 16));
    expect(months.map((m) => m.month), ['2026-08', '2026-09', '2026-10']);
    expect(months[0].expense, 50000);
    expect([months[1].income, months[1].expense], [0, 0]);
    expect(months[2].income, 70000);
  });

  test('continuity gap detected', () async {
    await ledger.insertTxn(
      tx(
        ref: 'a',
        at: oct,
        amount: 1,
        direction: Direction.incoming,
        balance: 1000000,
      ),
    );
    await ledger.insertTxn(
      tx(
        ref: 'b',
        at: oct.add(const Duration(hours: 1)),
        amount: 100000,
        balance: 850000,
      ),
    );
    final gaps = await ledger.continuityGaps();
    expect(gaps, hasLength(1));
    expect(gaps.single.before.ref, 'a');
    expect(gaps.single.after.ref, 'b');
  });

  test('no continuity gap when balances add up', () async {
    await ledger.insertTxn(
      tx(
        ref: 'a',
        at: oct,
        amount: 1,
        direction: Direction.incoming,
        balance: 1000000,
      ),
    );
    await ledger.insertTxn(
      tx(
        ref: 'b',
        at: oct.add(const Duration(hours: 1)),
        amount: 100000,
        balance: 900000,
      ),
    );
    await ledger.insertTxn(
      tx(
        ref: 'c',
        at: oct.add(const Duration(hours: 2)),
        amount: 50000,
        direction: Direction.incoming,
        balance: 950000,
      ),
    );
    expect(await ledger.continuityGaps(), isEmpty);
  });

  test('accountIdFor reuses existing', () async {
    expect(await ledger.accountIdFor(bankCode: 'VCB', last4: '1234'), acc);
    expect(
      await ledger.accountIdFor(bankCode: 'VCB', last4: '9999'),
      isNot(acc),
    );
    final noLast4 = await ledger.accountIdFor(bankCode: 'VCB');
    expect(await ledger.accountIdFor(bankCode: 'VCB'), noLast4);
  });
}
