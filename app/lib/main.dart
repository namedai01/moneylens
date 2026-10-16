import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'dashboard/dashboard_screen.dart';
import 'data/settings_store.dart';
import 'onboarding/connect_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();
  await services.rules.load();
  await services.ingest.run();
  final onboarded =
      await services.settings.get(SettingKeys.onboardingDone) != null;
  runApp(MoneyLensApp(services: services, onboarded: onboarded));
  unawaited(_refreshRules(services));
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

class _MoneyLensAppState extends State<MoneyLensApp> {
  late bool _onboarded = widget.onboarded;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyLens',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: _onboarded
          ? DashboardScreen(services: widget.services)
          : ConnectScreen(
              services: widget.services,
              onDone: () => setState(() => _onboarded = true),
            ),
    );
  }
}
