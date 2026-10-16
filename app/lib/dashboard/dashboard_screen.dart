import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/settings_store.dart';
import '../data/txn.dart';
import '../data/vn_time.dart';
import '../format.dart';
import '../report/failed_events_screen.dart';
import '../status/status_screen.dart';
import '../theme.dart';
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
  bool _needsSignIn = false;

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
    final needsSignIn =
        await s.settings.get(SettingKeys.lastSyncError) == 'auth_required';
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _txns = txns.reversed.toList();
      _history = history;
      _failed = failed;
      _gaps = gaps;
      _needsSignIn = needsSignIn;
    });
  }

  Future<void> _openStatus() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatusScreen(services: widget.services),
      ),
    );
    await reload();
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

  /// Gaps keyed by the later transaction: the marker sits right below it,
  /// between the two rows whose balances don't add up.
  Map<int, ContinuityGap> get _gapAfter => {
    for (final g in _gaps) g.after.id: g,
  };

  /// Month of the newest gap, where the banner leads.
  String? get _gapMonth => _gaps.isEmpty
      ? null
      : monthKeyOf(
          _gaps
              .map((g) => g.after.occurredAt)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        );

  void _selectMonth(String month) {
    if (month == _month) return;
    setState(() => _month = month);
    reload();
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
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openStatus,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final report = await widget.services.ingest.run();
          if (report.parsed > 0) widget.onLocalChange?.call();
          await reload();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (_failed > 0)
              _Banner(
                icon: Icons.report_gmailerrorred_rounded,
                color: theme.colorScheme.errorContainer,
                onColor: theme.colorScheme.onErrorContainer,
                text:
                    '$_failed thông báo chưa đọc được — có thể đang thiếu '
                    'giao dịch. Bấm để gửi mẫu (đã che số).',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        FailedEventsScreen(services: widget.services),
                  ),
                ),
              ),
            if (_needsSignIn)
              _Banner(
                icon: Icons.cloud_off_rounded,
                color: theme.colorScheme.errorContainer,
                onColor: theme.colorScheme.onErrorContainer,
                text:
                    'Chưa sao lưu được: cần đăng nhập lại Google. Bấm để mở '
                    'Trạng thái rồi chọn "Đồng bộ ngay".',
                onTap: _openStatus,
              ),
            if (_gaps.isNotEmpty)
              _Banner(
                icon: Icons.link_off_rounded,
                color: theme.colorScheme.tertiaryContainer,
                onColor: theme.colorScheme.onTertiaryContainer,
                text: _gapsText(_gaps),
                onTap: _gapMonth == _month
                    ? null
                    : () => _selectMonth(_gapMonth!),
              ),
            _MonthSwitcher(
              month: _month,
              onPrevious: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
            ),
            if (summary != null) _MonthTotals(summary),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 20),
              MonthChart(
                months: _history,
                selected: _month,
                onSelect: _selectMonth,
              ),
            ],
            const SizedBox(height: 28),
            if (summary != null && _txns.isEmpty)
              const _EmptyMonth()
            else
              for (final day in _byDay(_txns)) ...[
                _DayHeader(day),
                for (final t in day.txns) ...[
                  _TxnTile(t, onToggle: () => _toggle(t)),
                  if (_gapAfter[t.id] case final gap?) _GapMarker(gap),
                ],
                const SizedBox(height: 16),
              ],
          ],
        ),
      ),
    );
  }
}

String _gapsText(List<ContinuityGap> gaps) {
  if (gaps.length > 1) {
    return 'Số dư không khớp ở ${gaps.length} chỗ — có thể thiếu giao dịch.';
  }
  final g = gaps.single;
  return 'Có thể thiếu giao dịch giữa ${formatVnTime(g.before.occurredAt)} '
      'và ${formatVnTime(g.after.occurredAt)} (số dư không khớp).';
}

/// Inline note between two transactions whose balances don't add up.
class _GapMarker extends StatelessWidget {
  final ContinuityGap gap;

  const _GapMarker(this.gap);

  /// Net amount of whatever was missed between the two.
  int get _missing =>
      gap.after.balanceAfter! -
      (gap.before.balanceAfter! + gap.after.signedAmount);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.link_off_rounded,
            size: 16,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Số dư lệch ${formatVnd(_missing, signed: true)} — '
              'có thể thiếu giao dịch ở đây',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Transactions of one Vietnam-time day, newest first.
class _Day {
  final String label;
  final List<Txn> txns = [];

  _Day(this.label);

  /// Net of the transactions still counted in the totals.
  int get net =>
      txns.where((t) => !t.excluded).fold(0, (sum, t) => sum + t.signedAmount);
}

List<_Day> _byDay(List<Txn> txns) {
  final days = <_Day>[];
  for (final t in txns) {
    final label = formatVnDay(t.occurredAt);
    if (days.isEmpty || days.last.label != label) days.add(_Day(label));
    days.last.txns.add(t);
  }
  return days;
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color onColor;
  final String text;
  final VoidCallback? onTap;

  const _Banner({
    required this.icon,
    required this.color,
    required this.onColor,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: onColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: TextStyle(color: onColor)),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 20, color: onColor),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MonthSwitcher extends StatelessWidget {
  final String month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final muted = MoneyColors.of(context).muted;
    return Row(
      children: [
        Text('Tháng ', style: TextStyle(color: muted)),
        Text(
          formatMonth(month),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Tháng trước',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: onPrevious,
        ),
        IconButton(
          tooltip: 'Tháng sau',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Spending is the headline; income and net sit quietly beneath it.
class _MonthTotals extends StatelessWidget {
  final MonthSummary summary;

  const _MonthTotals(this.summary);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final net = summary.net;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          key: const Key('expense'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đã chi',
              style: theme.textTheme.labelLarge?.copyWith(color: money.muted),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatVnd(summary.expense),
                style: theme.textTheme.displaySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _Figure(
              'Thu vào',
              formatVnd(summary.income),
              money.income,
              const Key('income'),
            ),
            const SizedBox(width: 24),
            _Figure(
              'Chênh lệch',
              formatVnd(net, signed: true),
              net < 0 ? money.expense : money.income,
              const Key('net'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Figure(this.label, this.value, this.color, Key key) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final _Day day;

  const _DayHeader(this.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: money.line)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(day.label, style: theme.textTheme.labelLarge)),
          Text(
            formatVnd(day.net, signed: true),
            style: theme.textTheme.labelMedium,
          ),
          // Lines the subtotal up with the amounts above the eye buttons.
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 32,
            color: MoneyColors.of(context).muted,
          ),
          const SizedBox(height: 8),
          Text(
            'Chưa có giao dịch trong tháng này.',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Giao dịch hiện ở đây khi VCB Digibank báo biến động số dư.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Txn txn;
  final VoidCallback onToggle;

  const _TxnTile(this.txn, {required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final excluded = txn.excluded;
    final incoming = txn.direction == Direction.incoming;
    return Opacity(
      opacity: excluded ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                formatVnClock(txn.occurredAt),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Text(
                txn.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatVnd(txn.signedAmount, signed: true),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: incoming ? money.income : null,
                decoration: excluded ? TextDecoration.lineThrough : null,
              ),
            ),
            SizedBox(
              width: 48,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: money.muted,
                tooltip: excluded
                    ? 'Tính lại vào thống kê'
                    : 'Ẩn khỏi thống kê',
                icon: Icon(
                  excluded
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: onToggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
