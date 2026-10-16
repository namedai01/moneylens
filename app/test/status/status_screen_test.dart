import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/status/status_screen.dart';

import '../support/capture_db_fixture.dart';
import '../support/services_fixture.dart';

void main() {
  late Directory dir;
  String? clipboard;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('status');
    clipboard = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('moneylens/listener'),
      (call) async => call.method == 'hasAccess' ? true : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => 1, // granted
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });

  tearDown(() => dir.delete(recursive: true));

  testWidgets('copy all puts only masked notifications on the clipboard', (
    tester,
  ) async {
    final s = (await tester.runAsync(
      () => testServices(dir, [
        rawRow(
          bigText:
              'Số dư TK VCB 0011004123456 -1,500,000 VND lúc 16-10-2026 '
              '10:24:27. Số dư 8,500,000 VND. Ref MBVCB.112233.TRAN B',
          postedAt: DateTime.utc(2026, 10, 16, 3),
        ),
        rawRow(
          bigText: 'Mã OTP của Quý khách là 482913.',
          postedAt: DateTime.utc(2026, 10, 16, 4),
        ),
      ]),
    ))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: StatusScreen(services: s)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Sao chép tất cả'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(clipboard, isNotNull);
    expect(clipboard, isNot(contains('0011004123456')));
    expect(clipboard, isNot(contains('1,500,000')));
    expect(clipboard, isNot(contains('482913')));
    expect(clipboard, isNot(contains('TRAN')));
    expect(clipboard, contains('Số dư TK VCB 9999999999999 -9,999,999 VND'));
    await tester.pumpWidget(const SizedBox());
  });
}
