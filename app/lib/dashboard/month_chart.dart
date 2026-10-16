import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/txn.dart';
import '../theme.dart';

/// Income and expense bars for the last months, oldest on the left. The
/// [selected] month stands out; tapping a month selects it.
class MonthChart extends StatelessWidget {
  final List<MonthSummary> months;
  final String selected;
  final ValueChanged<String> onSelect;

  const MonthChart({
    super.key,
    required this.months,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final top = months.fold<int>(
      1,
      (m, s) => [m, s.income, s.expense].reduce((a, b) => a > b ? a : b),
    );
    final track = BackgroundBarChartRodData(
      show: true,
      toY: top.toDouble(),
      color: Colors.transparent,
    );
    return SizedBox(
      height: 112,
      child: BarChart(
        BarChartData(
          maxY: top.toDouble(),
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            handleBuiltInTouches: false,
            allowTouchBarBackDraw: true,
            touchCallback: (event, response) {
              final i = response?.spot?.touchedBarGroupIndex;
              if (event is FlTapUpEvent && i != null) onSelect(months[i].month);
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, _) {
                  final m = months[v.toInt()].month;
                  final on = m == selected;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      m.substring(5),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: on ? theme.colorScheme.onSurface : money.muted,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  for (final (value, color) in [
                    (months[i].income, money.income),
                    (months[i].expense, money.expense),
                  ])
                    BarChartRodData(
                      toY: value.toDouble(),
                      width: 6,
                      borderRadius: BorderRadius.circular(2),
                      color: months[i].month == selected
                          ? color
                          : color.withValues(alpha: 0.28),
                      backDrawRodData: track,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
