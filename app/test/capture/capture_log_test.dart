import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/capture/capture_log.dart';
import 'package:moneylens/capture/captured_notification.dart';

CapturedNotification _n(String pkg, int minute) => CapturedNotification(
  packageName: pkg,
  title: 'title $minute',
  text: 'text $minute',
  bigText: null,
  postedAt: DateTime.utc(2026, 10, 16, 10, minute),
);

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('capture_log_test');
    file = File('${dir.path}/capture_log.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('stores vcb content, only counts others', () async {
    final log = CaptureLog(file);
    await log.record(_n('com.VCB', 1));
    await log.record(_n('com.zing', 2));

    final recent = await log.recentVcb();
    expect(recent, hasLength(1));
    expect(recent.single.packageName, 'com.VCB');
    expect(file.readAsStringSync(), isNot(contains('text 2')));

    final counts = await log.packageCounts();
    expect(counts['com.zing'], 1);
    expect(counts['com.VCB'], 1);
  });

  test('appends multiple entries newest first', () async {
    final log = CaptureLog(file);
    await log.record(_n('com.VCB', 1));
    await log.record(_n('com.VCB', 3));
    await log.record(_n('com.VCB', 2));

    final minutes = (await log.recentVcb()).map((n) => n.postedAt.minute);
    expect(minutes, [3, 2, 1]);
  });

  test('caps at 50', () async {
    final log = CaptureLog(file);
    for (var i = 0; i < 60; i++) {
      await log.record(_n('com.VCB', i));
    }

    final all = await log.recentVcb(limit: 100);
    expect(all, hasLength(50));
    expect(all.last.postedAt.minute, 10);
    expect(all.first.postedAt.minute, 59);
  });

  test('corrupt file returns empty', () async {
    file.writeAsStringSync('not json');
    final log = CaptureLog(file);

    expect(await log.recentVcb(), isEmpty);
    expect(await log.packageCounts(), isEmpty);
  });
}
