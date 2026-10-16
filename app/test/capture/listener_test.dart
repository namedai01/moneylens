import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/listener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('moneylens/listener'), (
          call,
        ) async {
          calls.add(call.method);
          return switch (call.method) {
            'hasAccess' => true,
            'captureDbPath' =>
              '/data/user/0/vn.moneylens.app/databases/capture.db',
            _ => null,
          };
        });
  });

  test('hasNotificationAccess asks the native side', () async {
    expect(await hasNotificationAccess(), isTrue);
    expect(calls, ['hasAccess']);
  });

  test(
    'captureDbPath uses the database the native listener writes to',
    () async {
      expect(
        await captureDbPath(),
        '/data/user/0/vn.moneylens.app/databases/capture.db',
      );
      expect(calls, ['captureDbPath']);
    },
  );

  test('openNotificationAccessSettings invokes openSettings', () async {
    await openNotificationAccessSettings();
    expect(calls, ['openSettings']);
  });
}
