import '../capture/raw_event.dart';
import '../capture/raw_event_source.dart';
import '../data/ledger.dart';
import '../data/parse_log.dart';
import '../data/txn.dart';
import '../parser/parser_rules.dart';

class IngestReport {
  final int parsed;
  final int ignored;
  final int failed;
  final int duplicates;

  const IngestReport({
    this.parsed = 0,
    this.ignored = 0,
    this.failed = 0,
    this.duplicates = 0,
  });
}

/// Turns raw notifications from `capture.db` into ledger transactions.
///
/// Safe to re-run: a raw is reprocessed only if its parse result was never
/// recorded, and `raw_event_id` is unique on transactions, so a crash between
/// the two writes cannot double-count.
class Ingest {
  final RawEventSource source;
  final Ledger ledger;
  final ParseLog parseLog;
  final ParserRules Function() rules;

  Future<IngestReport>? _running;

  Ingest({
    required this.source,
    required this.ledger,
    required this.parseLog,
    required this.rules,
  });

  /// Processes every raw not seen yet. Concurrent calls share one pass.
  Future<IngestReport> run() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<IngestReport> _run() async {
    final c = _Counter();
    while (true) {
      final batch = await source.after(await parseLog.maxRawId());
      if (batch.isEmpty) break;
      for (final raw in batch) {
        await _process(raw, c);
      }
    }
    return c.report();
  }

  /// Retries raws that failed, with the current rules. Existing transactions
  /// are left untouched.
  Future<IngestReport> reparseFailed() async {
    final c = _Counter();
    for (final raw in await source.byIds(await parseLog.failedIds())) {
      await _process(raw, c);
    }
    return c.report();
  }

  Future<void> _process(RawEvent raw, _Counter c) async {
    final r = rules();
    switch (r.parse(raw)) {
      case Parsed(:final txn):
        final inserted = await ledger.insertTxn(
          NewTxn(
            accountId: await ledger.accountIdFor(
              bankCode: txn.bankCode,
              last4: txn.accountLast4,
            ),
            rawEventId: raw.id,
            ref: txn.ref,
            source: 'android_notif',
            occurredAt: txn.occurredAt,
            amount: txn.amount,
            direction: txn.direction,
            balanceAfter: txn.balanceAfter,
            description: txn.description,
          ),
        );
        inserted ? c.parsed++ : c.duplicates++;
        await parseLog.record(raw.id, 'parsed', rulesVersion: r.version);
      case Ignored(:final reason):
        c.ignored++;
        await parseLog.record(
          raw.id,
          'ignored',
          error: reason,
          rulesVersion: r.version,
        );
      case Failed(:final reason):
        c.failed++;
        await parseLog.record(
          raw.id,
          'failed',
          error: reason,
          rulesVersion: r.version,
        );
    }
  }
}

class _Counter {
  var parsed = 0, ignored = 0, failed = 0, duplicates = 0;

  IngestReport report() => IngestReport(
    parsed: parsed,
    ignored: ignored,
    failed: failed,
    duplicates: duplicates,
  );
}
