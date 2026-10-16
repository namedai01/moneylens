import 'package:flutter/services.dart';

/// Bridge to the native `VcbNotificationListener` (Android only).
///
/// The listener runs as a system-bound Kotlin service and writes `capture.db`
/// itself, so no Dart code has to run in the background.
const _channel = MethodChannel('moneylens/listener');

Future<bool> hasNotificationAccess() async =>
    await _channel.invokeMethod<bool>('hasAccess') ?? false;

Future<void> openNotificationAccessSettings() =>
    _channel.invokeMethod<void>('openSettings');

/// Path of `capture.db`; the native side creates it before answering.
Future<String> captureDbPath() async =>
    (await _channel.invokeMethod<String>('captureDbPath'))!;

/// Debug builds only: stores a fake VCB notification as if it was posted now.
Future<bool> debugInjectVcb({
  required String title,
  required String bigText,
}) async =>
    await _channel.invokeMethod<bool>('debugInjectVcb', {
      'title': title,
      'bigText': bigText,
    }) ??
    false;
