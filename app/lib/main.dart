import 'package:flutter/material.dart';

import 'status/status_screen.dart';

void main() {
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
