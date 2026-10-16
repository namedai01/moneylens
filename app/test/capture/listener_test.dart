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
            'logPath' => '/data/user/0/vn.moneylens.app/app_flutter/x.json',
            _ => null,
          };
        });
  });

  test('hasNotificationAccess asks the native side', () async {
    expect(await hasNotificationAccess(), isTrue);
    expect(calls, ['hasAccess']);
  });

  test('captureLogFile uses the path the native listener writes to', () async {
    final f = await captureLogFile();
    expect(f.path, '/data/user/0/vn.moneylens.app/app_flutter/x.json');
  });

  test('openNotificationAccessSettings invokes openSettings', () async {
    await openNotificationAccessSettings();
    expect(calls, ['openSettings']);
  });
}
