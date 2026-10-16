import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_notification_listener_plus/flutter_notification_listener_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'capture_log.dart';
import 'captured_notification.dart';

/// Port name the UI isolate listens on to refresh when a notification lands.
const captureUiPortName = 'moneylens_capture_ui';

/// Converts the plugin's raw event map into our model.
///
/// Keys come from the plugin's Kotlin side: `package_name`, `title`, `text`,
/// `bigText` (from `android.bigText`) and `timestamp` (`postTime`, epoch ms).
CapturedNotification? capturedFromRaw(Map<dynamic, dynamic> raw) {
  final packageName = raw['package_name'] as String?;
  if (packageName == null || packageName.isEmpty) return null;
  final ts = raw['timestamp'] as int?;
  return CapturedNotification(
    packageName: packageName,
    title: raw['title'] as String?,
    text: raw['text'] as String?,
    bigText: raw['bigText'] as String?,
    postedAt: ts == null
        ? DateTime.now().toUtc()
        : DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
  );
}

Future<File> captureLogFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/capture_log.json');
}

/// Runs in the plugin's background isolate, even when the UI is closed.
@pragma('vm:entry-point')
Future<void> onNotificationEvent(NotificationEvent evt) async {
  final raw = evt.raw;
  if (raw == null) return;
  final n = capturedFromRaw(raw);
  if (n == null) return;

  await CaptureLog(await captureLogFile()).record(n);

  IsolateNameServer.lookupPortByName(captureUiPortName)?.send(null);
}

Future<void> initListener() async {
  await NotificationsListener.initialize(callbackHandle: onNotificationEvent);
  if (await hasNotificationAccess() &&
      !(await NotificationsListener.isRunning ?? false)) {
    await NotificationsListener.startService(
      foreground: true,
      title: 'MoneyLens',
      description: 'Đang theo dõi thông báo biến động số dư',
    );
  }
}

Future<bool> hasNotificationAccess() async =>
    await NotificationsListener.hasPermission ?? false;

Future<void> openNotificationAccessSettings() =>
    NotificationsListener.openPermissionSettings();

/// Lets the UI isolate know when the background isolate recorded something.
ReceivePort registerCaptureUiPort() {
  IsolateNameServer.removePortNameMapping(captureUiPortName);
  final port = ReceivePort();
  IsolateNameServer.registerPortWithName(port.sendPort, captureUiPortName);
  return port;
}
