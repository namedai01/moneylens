import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/app_services.dart';
import 'package:moneylens/dashboard/dashboard_screen.dart';

import '../support/capture_db_fixture.dart';
import '../support/samples.dart';
import '../support/services_fixture.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('dash'));
  tearDown(() => dir.delete(recursive: true));

  final now = DateTime.utc(2026, 10, 16, 6);

  Future<AppServices> services(
    WidgetTester tester,
    List<Map<String, Object?>> raws,
  ) async {
    final s = (await tester.runAsync(() async {
      final s = await testServices(dir, raws);
      await s.ingest.run();
      return s;
    }))!;
    return s;
  }

  Future<void> show(WidgetTester tester, AppServices s) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(services: s, now: () => now),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('shows month totals and transactions', (tester) async {
    final s = await services(tester, [
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1', amount: 300000, balance: 700000),
        postedAt: now,
      ),
      rawRow(
        bigText: vcbOut(
          ref: 'MBVCB.2',
          amount: 200000,
          balance: 500000,
          time: '16-10-2026 11:00:00',
        ),
        postedAt: now,
      ),
    ]);
    await show(tester, s);
    expect(find.text('10/2026'), findsOneWidget);
    expect(find.text('500.000 ₫'), findsWidgets); // expense card
    expect(find.text('−300.000 ₫'), findsOneWidget);
    expect(find.text('−200.000 ₫'), findsOneWidget);
  });

  testWidgets('hiding a transaction lowers the expense total', (tester) async {
    final s = await services(tester, [
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1', amount: 300000, balance: 700000),
        postedAt: now,
      ),
      rawRow(
        bigText: vcbOut(
          ref: 'MBVCB.2',
          amount: 200000,
          balance: 500000,
          time: '16-10-2026 11:00:00',
        ),
        postedAt: now,
      ),
    ]);
    await show(tester, s);
    // Newest first: the first row is the 200.000 ₫ one.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Ẩn khỏi thống kê').first);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('expense')),
        matching: find.text('300.000 ₫'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Tính lại vào thống kê'), findsOneWidget);
  });

  testWidgets('failed raws show a badge', (tester) async {
    final s = await services(tester, [
      rawRow(bigText: unknownBalanceText, postedAt: now),
    ]);
    await show(tester, s);
    expect(find.textContaining('1 thông báo chưa đọc được'), findsOneWidget);
  });

  testWidgets('continuity gap shows a warning', (tester) async {
    final s = await services(tester, [
      rawRow(
        bigText: vcbOut(ref: 'MBVCB.1', amount: 100000, balance: 900000),
        postedAt: now,
      ),
      rawRow(
        bigText: vcbOut(
          ref: 'MBVCB.2',
          amount: 100000,
          balance: 500000,
          time: '16-10-2026 12:00:00',
        ),
        postedAt: now,
      ),
    ]);
    await show(tester, s);
    expect(find.textContaining('Có thể thiếu giao dịch'), findsOneWidget);
  });
}
