import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/data/parse_log.dart';

import '../support/app_db_fixture.dart';

void main() {
  test('maxRawId of empty log is 0', () async {
    expect(await ParseLog(await memoryAppDb()).maxRawId(), 0);
  });

  test('record upserts by raw id', () async {
    final log = ParseLog(await memoryAppDb());
    await log.record(4, 'failed', error: 'no-rule', rulesVersion: 1);
    await log.record(4, 'parsed', rulesVersion: 2);
    expect(await log.maxRawId(), 4);
    expect(await log.failedCount(), 0);
  });

  test('failedIds only returns failed', () async {
    final log = ParseLog(await memoryAppDb());
    await log.record(1, 'parsed', rulesVersion: 1);
    await log.record(2, 'failed', error: 'x', rulesVersion: 1);
    await log.record(3, 'ignored', rulesVersion: 1);
    await log.record(5, 'failed', error: 'y', rulesVersion: 1);
    expect(await log.failedIds(), [2, 5]);
    expect(await log.failedCount(), 2);
  });
}
