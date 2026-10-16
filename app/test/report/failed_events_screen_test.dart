import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/dashboard/dashboard_screen.dart';

import '../support/capture_db_fixture.dart';
import '../support/services_fixture.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('failed'));
  tearDown(() => dir.delete(recursive: true));

  testWidgets('badge opens masked samples ready to share', (tester) async {
    final s = (await tester.runAsync(() async {
      final s = await testServices(dir, [
        rawRow(
          bigText: 'Quý khách có biến động số dư 1,234,567 VND từ NGUYEN VAN A',
          postedAt: DateTime.utc(2026, 10, 16, 3),
        ),
      ]);
      await s.ingest.run();
      return s;
    }))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: DashboardScreen(services: s)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.textContaining('chưa đọc được'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // The new route loads from SQLite: let real I/O finish.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    final text = field.controller!.text;
    expect(text, contains('9,999,999 VND'));
    expect(text, isNot(contains('1,234,567')));
    expect(text, isNot(contains('NGUYEN')));
    expect(find.text('Gửi mẫu lỗi'), findsOneWidget);
  });
}
