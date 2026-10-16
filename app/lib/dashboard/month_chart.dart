import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/txn.dart';

/// Income and expense bars for the last months, oldest on the left.
class MonthChart extends StatelessWidget {
  final List<MonthSummary> months;

  const MonthChart({super.key, required this.months});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Text(
                  months[v.toInt()].month.substring(5),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: months[i].income.toDouble(),
                    color: scheme.primary,
                    width: 6,
                  ),
                  BarChartRodData(
                    toY: months[i].expense.toDouble(),
                    color: scheme.error,
                    width: 6,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
