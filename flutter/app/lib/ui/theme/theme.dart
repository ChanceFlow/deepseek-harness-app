/// App theme — port of Theme.kt: plain Material 3 light/dark defaults.
library;

import 'package:flutter/material.dart';

class DshTheme {
  const DshTheme._();

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      );
}
