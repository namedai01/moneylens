import 'package:sqflite/sqflite.dart';

import 'txn.dart';
import 'vn_time.dart';

class Ledger {
  final Database db;
  final DateTime Function() _clock;

  Ledger(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  int _now() => _clock().millisecondsSinceEpoch;

  /// The account for [bankCode] + [last4], created on first sight.
  Future<int> accountIdFor({required String bankCode, String? last4}) async {
    final found = await db.query(
      'accounts',
      columns: ['id'],
      where: 'bank_code = ? AND last4 IS ?',
      whereArgs: [bankCode, last4],
    );
    if (found.isNotEmpty) return found.first['id']! as int;
    return db.insert('accounts', {
      'bank_code': bankCode,
      'kind': 'bank',
      'name': '$bankCode ${last4 ?? ''}'.trim(),
      'last4': last4,
      'created_at': _now(),
    });
  }

  /// False when the transaction is already stored (same Ref, or same
  /// time/amount/balance without a Ref).
  Future<bool> insertTxn(NewTxn t) async {
    final now = _now();
    final id = await db.insert('transactions', {
      'account_id': t.accountId,
      'raw_event_id': t.rawEventId,
      'ref': t.ref,
      'source': t.source,
      'occurred_at': t.occurredAt.millisecondsSinceEpoch,
      'amount': t.amount,
      'direction': t.direction.db,
      'balance_after': t.balanceAfter,
      'description': t.description,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return id != 0;
  }

  Future<void> setExcluded(int txnId, bool excluded) => db.update(
    'transactions',
    {'excluded': excluded ? 1 : 0, 'updated_at': _now()},
    where: 'id = ?',
    whereArgs: [txnId],
  );

  static const _select =
      'SELECT t.*, a.last4 FROM transactions t '
      'JOIN accounts a ON a.id = t.account_id';

  Future<List<Txn>> _query(String where, List<Object?> args) async {
    final rows = await db.rawQuery(
      '$_select $where ORDER BY t.occurred_at, t.id',
      args,
    );
    return rows.map(Txn.fromRow).toList();
  }

  Future<List<Txn>> all() => _query('', []);

  Future<List<Txn>> monthTxns(String monthKey) {
    final r = monthRangeUtc(monthKey);
    return _query('WHERE t.occurred_at >= ? AND t.occurred_at < ?', [
      r.start.millisecondsSinceEpoch,
      r.end.millisecondsSinceEpoch,
    ]);
  }

  Future<MonthSummary> monthSummary(String monthKey) async {
    final r = monthRangeUtc(monthKey);
    final rows = await db.rawQuery(
      '''
SELECT
  COALESCE(SUM(CASE WHEN direction = 'in' THEN amount END), 0) AS income,
  COALESCE(SUM(CASE WHEN direction = 'out' THEN amount END), 0) AS expense
FROM transactions
WHERE excluded = 0 AND occurred_at >= ? AND occurred_at < ?''',
      [r.start.millisecondsSinceEpoch, r.end.millisecondsSinceEpoch],
    );
    return MonthSummary(
      monthKey,
      income: rows.first['income']! as int,
      expense: rows.first['expense']! as int,
    );
  }

  /// The [n] months ending with the month of [now], oldest first.
  Future<List<MonthSummary>> lastMonths(int n, {required DateTime now}) async {
    final current = monthKeyOf(now);
    return [
      for (var i = n - 1; i >= 0; i--)
        await monthSummary(shiftMonth(current, -i)),
    ];
  }

  Future<DateTime?> latestUpdate() async {
    final rows = await db.rawQuery(
      'SELECT MAX(updated_at) AS m FROM transactions',
    );
    final m = rows.first['m'] as int?;
    return m == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m, isUtc: true);
  }

  /// Transactions created or changed after [t] (all of them when null).
  Future<int> changedSince(DateTime? t) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions WHERE updated_at > ?',
      [t?.millisecondsSinceEpoch ?? -1],
    );
    return rows.first['c']! as int;
  }

  Future<List<ContinuityGap>> continuityGaps() async {
    final txns = await _query('WHERE t.balance_after IS NOT NULL', []);
    final byAccount = <int, List<Txn>>{};
    for (final t in txns) {
      byAccount.putIfAbsent(t.accountId, () => []).add(t);
    }
    return [
      for (final list in byAccount.values)
        for (var i = 1; i < list.length; i++)
          if (list[i - 1].balanceAfter! + list[i].signedAmount !=
              list[i].balanceAfter!)
            ContinuityGap(list[i - 1], list[i]),
    ];
  }
}
