import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const background = Color(0xFFF7F5F1);
  static const ink = Color(0xFF24231F);
  static const accent = Color(0xFF8B6F5A);
  static const sage = Color(0xFFA9B0A1);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: background,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'PingFang SC',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: .86),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF805A3B),
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 68,
        backgroundColor: Color(0xFFF7F5F1),
        indicatorColor: Color(0xFFEAE2D7),
        indicatorShape: StadiumBorder(),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: Color(0xFF5C4632), fontSize: 12),
        ),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: Color(0xFF5C4632), size: 21),
        ),
      ),
    );
  }
}
