import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'dashboard/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();
  await services.rules.load();
  await services.ingest.run();
  runApp(MoneyLensApp(services: services));
  unawaited(_refreshRules(services));
}

/// Newer rules may read notifications that failed before.
Future<void> _refreshRules(AppServices services) async {
  if (await services.rules.refresh()) {
    await services.ingest.reparseFailed();
  }
}

class MoneyLensApp extends StatelessWidget {
  final AppServices services;

  const MoneyLensApp({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyLens',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: DashboardScreen(services: services),
    );
  }
}
