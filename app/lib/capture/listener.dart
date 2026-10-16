import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the native `VcbNotificationListener` (Android only).
///
/// The listener runs as a system-bound Kotlin service and writes the capture
/// log itself, so no Dart code has to run in the background.
const _channel = MethodChannel('moneylens/listener');

Future<bool> hasNotificationAccess() async =>
    await _channel.invokeMethod<bool>('hasAccess') ?? false;

Future<void> openNotificationAccessSettings() =>
    _channel.invokeMethod<void>('openSettings');

/// The capture log written by the native listener.
Future<File> captureLogFile() async =>
    File((await _channel.invokeMethod<String>('logPath'))!);
