import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../app_services.dart';

const periodicSyncTask = 'moneylens.periodicSync';

/// Registers the ~6h background ingest + sync. Kotlin never schedules work on
/// a new notification: the Sheet may lag until the next run or app open.
Future<void> scheduleBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    periodicSyncTask,
    periodicSyncTask,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Debug builds: run the background job once, now, in its own isolate.
Future<void> debugRunBackgroundSyncNow() => Workmanager().registerOneOffTask(
  'moneylens.debugSync',
  periodicSyncTask,
  existingWorkPolicy: ExistingWorkPolicy.replace,
);

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final services = await AppServices.open(background: true);
      await services.rules.load();
      if (await services.rules.refresh()) {
        await services.ingest.reparseFailed();
      }
      // Without a silent token this records `auth_required`; the app then
      // asks the user to tap "Đồng bộ ngay".
      final result = await services.sync.sync();
      debugPrint('MoneyLens background sync: ${result.name}');
    } catch (_) {
      // Errors are kept in settings; returning true avoids retry storms.
    }
    return true;
  });
}
