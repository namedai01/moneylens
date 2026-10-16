enum Direction {
  incoming('in'),
  outgoing('out');

  final String db;

  const Direction(this.db);

  static Direction fromDb(String v) =>
      values.firstWhere((d) => d.db == v, orElse: () => throw ArgumentError(v));
}

/// A transaction about to be stored.
class NewTxn {
  final int accountId;
  final int? rawEventId;
  final String? ref;
  final String source;
  final DateTime occurredAt;
  final int amount;
  final Direction direction;
  final int? balanceAfter;
  final String description;

  const NewTxn({
    required this.accountId,
    required this.rawEventId,
    required this.ref,
    required this.source,
    required this.occurredAt,
    required this.amount,
    required this.direction,
    required this.balanceAfter,
    required this.description,
  });
}

/// A stored transaction. Times are UTC.
class Txn {
  final int id;
  final int accountId;
  final String? accountLast4;
  final int? rawEventId;
  final String? ref;
  final String source;
  final DateTime occurredAt;
  final int amount;
  final Direction direction;
  final int? balanceAfter;
  final String description;
  final bool excluded;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Txn({
    required this.id,
    required this.accountId,
    required this.accountLast4,
    required this.rawEventId,
    required this.ref,
    required this.source,
    required this.occurredAt,
    required this.amount,
    required this.direction,
    required this.balanceAfter,
    required this.description,
    required this.excluded,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Positive for money in, negative for money out.
  int get signedAmount => direction == Direction.incoming ? amount : -amount;

  factory Txn.fromRow(Map<String, Object?> r) {
    DateTime t(String k) =>
        DateTime.fromMillisecondsSinceEpoch(r[k]! as int, isUtc: true);
    return Txn(
      id: r['id']! as int,
      accountId: r['account_id']! as int,
      accountLast4: r['last4'] as String?,
      rawEventId: r['raw_event_id'] as int?,
      ref: r['ref'] as String?,
      source: r['source']! as String,
      occurredAt: t('occurred_at'),
      amount: r['amount']! as int,
      direction: Direction.fromDb(r['direction']! as String),
      balanceAfter: r['balance_after'] as int?,
      description: r['description']! as String,
      excluded: r['excluded'] == 1,
      createdAt: t('created_at'),
      updatedAt: t('updated_at'),
    );
  }
}

class MonthSummary {
  /// `YYYY-MM`, Vietnam time.
  final String month;
  final int income;
  final int expense;

  const MonthSummary(this.month, {required this.income, required this.expense});

  int get net => income - expense;
}

/// Two consecutive transactions of one account whose balances don't add up:
/// something between them was probably missed.
class ContinuityGap {
  final Txn before;
  final Txn after;

  const ContinuityGap(this.before, this.after);
}
