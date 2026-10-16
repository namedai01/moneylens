import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/onboarding/restore_dialog.dart';
import 'package:moneylens/sync/sheets_gateway.dart';

void main() {
  final found = [
    SheetFile(
      id: 'new',
      name: 'MoneyLens',
      modifiedAt: DateTime.utc(2026, 10, 16, 3, 5),
    ),
    const SheetFile(id: 'old', name: 'MoneyLens cũ'),
  ];

  /// Opens the dialog and returns a getter for what it popped.
  Future<String? Function()> open(WidgetTester tester) async {
    String? result = 'not closed';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await pickRestoreSheet(context, found),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('restores the newest Sheet by default', (tester) async {
    final result = await open(tester);
    expect(find.text('Sửa lần cuối 16/10 10:05'), findsOneWidget);
    await tester.tap(find.text('Khôi phục'));
    await tester.pumpAndSettle();
    expect(result(), 'new');
  });

  testWidgets('another Sheet can be picked', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('MoneyLens cũ'));
    await tester.pump();
    await tester.tap(find.text('Khôi phục'));
    await tester.pumpAndSettle();
    expect(result(), 'old');
  });

  testWidgets('new Sheet returns null; back does not close', (tester) async {
    final result = await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Khôi phục dữ liệu?'), findsOneWidget);
    await tester.tap(find.text('Tạo Sheet mới'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
