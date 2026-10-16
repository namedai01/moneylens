import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'dashboard/dashboard_screen.dart';
import 'data/settings_store.dart';
import 'ingest/foreground_ingest.dart';
import 'onboarding/connect_screen.dart';
import 'sync/auto_sync.dart';
import 'sync/background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();
  await services.rules.load();
  try {
    await services.ingest.run();
  } catch (_) {
    // Never block the app from opening; the next sync retries and records it.
  }
  final onboarded =
      await services.settings.get(SettingKeys.onboardingDone) != null;
  runApp(MoneyLensApp(services: services, onboarded: onboarded));
  unawaited(_refreshRules(services));
  unawaited(scheduleBackgroundSync().catchError((_) {}));
}

/// Newer rules may read notifications that failed before.
Future<void> _refreshRules(AppServices services) async {
  if (await services.rules.refresh()) {
    await services.ingest.reparseFailed();
  }
}

class MoneyLensApp extends StatefulWidget {
  final AppServices services;
  final bool onboarded;

  const MoneyLensApp({
    super.key,
    required this.services,
    required this.onboarded,
  });

  @override
  State<MoneyLensApp> createState() => _MoneyLensAppState();
}

class _MoneyLensAppState extends State<MoneyLensApp>
    with WidgetsBindingObserver {
  late bool _onboarded = widget.onboarded;
  final _dashboard = GlobalKey<DashboardScreenState>();
  late final _auto = AutoSync(
    widget.services.sync.sync,
    onDone: () => _dashboard.currentState?.reload(),
  );

  late final _poller = ForegroundIngest(
    widget.services.ingest.run,
    onNew: () {
      _dashboard.currentState?.reload();
      _auto.onLocalChange();
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auto.onAppResumed();
    _poller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auto.dispose();
    _poller.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _auto.onAppResumed();
        _poller.start();
      case AppLifecycleState.paused || AppLifecycleState.detached:
        _poller.stop();
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyLens',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: _onboarded
          ? DashboardScreen(
              key: _dashboard,
              services: widget.services,
              onLocalChange: _auto.onLocalChange,
            )
          : ConnectScreen(
              services: widget.services,
              onDone: () => setState(() => _onboarded = true),
            ),
    );
  }
}
