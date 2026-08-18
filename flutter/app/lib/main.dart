import 'package:flutter/material.dart';

void main() {
  runApp(const DshApp());
}

class DshApp extends StatelessWidget {
  const DshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepSeek Harness',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F6DF5), useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('Flutter rewrite in progress')),
      ),
    );
  }
}
