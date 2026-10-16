import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/listener.dart';

void main() {
  test('maps plugin raw event to CapturedNotification', () {
    final n = capturedFromRaw({
      'package_name': 'com.VCB',
      'title': 'Vietcombank',
      'text': 'Số dư TK VCB 0011…',
      'bigText': 'Số dư TK VCB 0011000000000 -500,000 VND',
      'timestamp': 1760585067123,
    });

    expect(n, isNotNull);
    expect(n!.packageName, 'com.VCB');
    expect(n.title, 'Vietcombank');
    expect(n.text, 'Số dư TK VCB 0011…');
    expect(n.bigText, 'Số dư TK VCB 0011000000000 -500,000 VND');
    expect(n.postedAt.millisecondsSinceEpoch, 1760585067123);
    expect(n.postedAt.isUtc, isTrue);
  });

  test('missing package name is dropped', () {
    expect(capturedFromRaw({'title': 'x', 'timestamp': 1}), isNull);
  });

  test('missing timestamp falls back to now', () {
    final before = DateTime.now().toUtc();
    final n = capturedFromRaw({'package_name': 'com.VCB'})!;
    expect(n.postedAt.isBefore(before), isFalse);
  });
}
