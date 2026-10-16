import 'dart:async';

import 'ingest.dart';

/// While the app is in front, picks up notifications the Kotlin listener
/// stored meanwhile (Kotlin never signals Dart). [onNew] fires when a pass
/// added transactions, e.g. to refresh the screen and schedule a sync.
class ForegroundIngest {
  final Future<IngestReport> Function() _ingest;
  final void Function() onNew;
  final Duration interval;

  Timer? _timer;

  ForegroundIngest(
    this._ingest, {
    required this.onNew,
    this.interval = const Duration(seconds: 30),
  });

  void start() => _timer ??= Timer.periodic(interval, (_) => _tick());

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      if ((await _ingest()).parsed > 0) onNew();
    } catch (_) {
      // Retried on the next tick; sync records persistent failures.
    }
  }
}
