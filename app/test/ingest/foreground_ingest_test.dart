import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylens/ingest/foreground_ingest.dart';
import 'package:moneylens/ingest/ingest.dart';

void main() {
  test('polls while started and reports only new transactions', () {
    fakeAsync((async) {
      var runs = 0;
      var news = 0;
      final reports = [
        const IngestReport(),
        const IngestReport(parsed: 2),
        const IngestReport(ignored: 1),
      ];
      final poller = ForegroundIngest(
        () async => reports[runs++ % reports.length],
        onNew: () => news++,
      );
      poller.start();
      async.elapse(const Duration(seconds: 29));
      expect(runs, 0);
      async.elapse(const Duration(seconds: 1));
      expect([runs, news], [1, 0]);
      async.elapse(const Duration(seconds: 30));
      expect([runs, news], [2, 1]);
      async.elapse(const Duration(seconds: 30));
      expect([runs, news], [3, 1]);
      poller.stop();
      async.elapse(const Duration(minutes: 5));
      expect(runs, 3);
    });
  });

  test('ingest errors never escape and polling continues', () {
    fakeAsync((async) {
      var runs = 0;
      final poller = ForegroundIngest(() async {
        runs++;
        throw StateError('db closed');
      }, onNew: () {});
      poller.start();
      async.elapse(const Duration(seconds: 61));
      expect(runs, 2);
      poller.stop();
    });
  });

  test('start twice keeps one timer', () {
    fakeAsync((async) {
      var runs = 0;
      final poller = ForegroundIngest(() async {
        runs++;
        return const IngestReport();
      }, onNew: () {});
      poller.start();
      poller.start();
      async.elapse(const Duration(seconds: 30));
      expect(runs, 1);
      poller.stop();
    });
  });
}
