import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capture/listener.dart';
import 'status/status_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isAndroid) await initListener();
  runApp(const MoneyLensApp());
}

class MoneyLensApp extends StatelessWidget {
  const MoneyLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyLens',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const StatusScreen(),
    );
  }
}
