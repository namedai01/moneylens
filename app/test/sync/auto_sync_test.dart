import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/sync/auto_sync.dart';
import 'package:moneylens/sync/sync_service.dart';

void main() {
  late int calls;
  late AutoSync auto;

  setUp(() {
    calls = 0;
    auto = AutoSync(() async {
      calls++;
      return SyncResult.ok;
    });
  });

  test('changes are batched into one sync after the debounce', () {
    fakeAsync((async) {
      auto.onLocalChange();
      async.elapse(const Duration(seconds: 10));
      auto.onLocalChange();
      async.elapse(const Duration(seconds: 20));
      auto.onLocalChange();
      async.elapse(const Duration(seconds: 59));
      expect(calls, 0);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      async.elapse(const Duration(minutes: 5));
      expect(calls, 1);
    });
  });

  test('resume syncs right away and drops a pending debounce', () {
    fakeAsync((async) {
      auto.onLocalChange();
      auto.onAppResumed();
      async.flushMicrotasks();
      expect(calls, 1);
      async.elapse(const Duration(minutes: 2));
      expect(calls, 1);
    });
  });

  test('dispose cancels the timer', () {
    fakeAsync((async) {
      auto.onLocalChange();
      auto.dispose();
      async.elapse(const Duration(minutes: 2));
      expect(calls, 0);
    });
  });

  test('sync errors never escape', () {
    fakeAsync((async) {
      final failing = AutoSync(() async => throw StateError('boom'));
      failing.onAppResumed();
      async.flushMicrotasks();
    });
  });
}
