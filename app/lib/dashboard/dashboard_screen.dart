import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/txn.dart';
import '../data/vn_time.dart';
import '../format.dart';
import '../status/status_screen.dart';
import 'month_chart.dart';

class DashboardScreen extends StatefulWidget {
  final AppServices services;
  final DateTime Function()? now;

  /// Called after the user changes a transaction (for auto sync).
  final VoidCallback? onLocalChange;

  const DashboardScreen({
    super.key,
    required this.services,
    this.now,
    this.onLocalChange,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  DateTime _now() => (widget.now ?? DateTime.now)();

  late String _month = monthKeyOf(_now());
  MonthSummary? _summary;
  List<Txn> _txns = [];
  List<MonthSummary> _history = [];
  int _failed = 0;
  List<ContinuityGap> _gaps = [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Re-reads everything shown; call after ingest or sync.
  Future<void> reload() async {
    final s = widget.services;
    final summary = await s.ledger.monthSummary(_month);
    final txns = await s.ledger.monthTxns(_month);
    final history = await s.ledger.lastMonths(12, now: _now());
    final failed = await s.parseLog.failedCount();
    final gaps = await s.ledger.continuityGaps();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _txns = txns.reversed.toList();
      _history = history;
      _failed = failed;
      _gaps = gaps;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = shiftMonth(_month, delta));
    reload();
  }

  Future<void> _toggle(Txn t) async {
    await widget.services.ledger.setExcluded(t.id, !t.excluded);
    widget.onLocalChange?.call();
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MoneyLens'),
        actions: [
          IconButton(
            tooltip: 'Trạng thái',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatusScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await widget.services.ingest.run();
          await reload();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_failed > 0)
              _Banner(
                color: theme.colorScheme.errorContainer,
                text:
                    '$_failed thông báo chưa đọc được — có thể đang thiếu '
                    'giao dịch.',
              ),
            for (final g in _gaps)
              _Banner(
                color: theme.colorScheme.tertiaryContainer,
                text:
                    'Có thể thiếu giao dịch giữa ${formatVnTime(g.before.occurredAt)} '
                    'và ${formatVnTime(g.after.occurredAt)} (số dư không khớp).',
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Tháng trước',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    formatMonth(_month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Tháng sau',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            if (summary != null)
              Row(
                children: [
                  _Total('Thu', summary.income, const Key('income')),
                  _Total('Chi', summary.expense, const Key('expense')),
                  _Total('Chênh lệch', summary.net, const Key('net')),
                ],
              ),
            const SizedBox(height: 16),
            if (_history.isNotEmpty) MonthChart(months: _history),
            const SizedBox(height: 16),
            if (_txns.isEmpty) const Text('Chưa có giao dịch trong tháng này.'),
            for (final t in _txns) _TxnTile(t, onToggle: () => _toggle(t)),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final String text;

  const _Banner({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
  );
}

class _Total extends StatelessWidget {
  final String label;
  final int amount;

  const _Total(this.label, this.amount, Key valueKey) : super(key: valueKey);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            FittedBox(child: Text(formatVnd(amount))),
          ],
        ),
      ),
    ),
  );
}

class _TxnTile extends StatelessWidget {
  final Txn txn;
  final VoidCallback onToggle;

  const _TxnTile(this.txn, {required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final excluded = txn.excluded;
    return Opacity(
      opacity: excluded ? 0.45 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(formatVnd(txn.signedAmount, signed: true)),
        subtitle: Text(
          '${formatVnTime(txn.occurredAt)} · ${txn.description}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: excluded ? 'Tính lại vào thống kê' : 'Ẩn khỏi thống kê',
          icon: Icon(
            excluded
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
