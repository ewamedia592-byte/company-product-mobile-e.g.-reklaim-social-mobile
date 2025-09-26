import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF002868); // Liberian flag blue
  static ThemeData light() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: primary),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
    );
  }
}
