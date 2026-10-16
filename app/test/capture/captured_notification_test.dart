import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/captured_notification.dart';

CapturedNotification _n({String? text, String? bigText}) =>
    CapturedNotification(
      packageName: 'com.VCB',
      title: 't',
      text: text,
      bigText: bigText,
      postedAt: DateTime.utc(2026, 10, 16),
    );

void main() {
  test('body prefers bigText', () {
    expect(_n(text: 'short', bigText: 'long').body, 'long');
  });

  test('body falls back to text', () {
    expect(_n(text: 'short', bigText: null).body, 'short');
    expect(_n(text: 'short', bigText: '').body, 'short');
    expect(_n(text: null, bigText: null).body, '');
  });

  test('json roundtrip keeps postedAt to the millisecond', () {
    final original = CapturedNotification(
      packageName: 'com.VCB',
      title: null,
      text: 'a',
      bigText: 'b',
      postedAt: DateTime.fromMillisecondsSinceEpoch(1760585067123, isUtc: true),
    );
    final copy = CapturedNotification.fromJson(original.toJson());
    expect(copy.packageName, original.packageName);
    expect(copy.title, isNull);
    expect(copy.text, 'a');
    expect(copy.bigText, 'b');
    expect(copy.postedAt.millisecondsSinceEpoch, 1760585067123);
  });

  test('isVcbPackage', () {
    expect(isVcbPackage('com.VCB'), isTrue);
    expect(isVcbPackage('com.vietcombank.digibank'), isTrue);
    expect(isVcbPackage('com.google.android.gm'), isFalse);
  });
}
