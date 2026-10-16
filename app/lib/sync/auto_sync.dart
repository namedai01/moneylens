import 'dart:async';

import 'sync_service.dart';

/// Foreground sync triggers: right away when the app comes back, and once
/// per burst of local changes. Background sync is `background.dart`.
class AutoSync {
  final Future<SyncResult> Function() _sync;
  final Duration debounce;

  /// Called after every attempt, e.g. to refresh what the screen shows.
  final void Function()? onDone;

  Timer? _timer;

  AutoSync(
    this._sync, {
    this.debounce = const Duration(minutes: 1),
    this.onDone,
  });

  void onAppResumed() {
    _timer?.cancel();
    _timer = null;
    _run();
  }

  void onLocalChange() {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      _run();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run() async {
    try {
      await _sync();
    } catch (_) {
      // The outcome is already recorded in settings; never crash the UI.
    }
    onDone?.call();
  }
}
