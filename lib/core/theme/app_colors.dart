import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

   static double border_radius = 5.0;
   static const Color inputBorder = Color(0xFFE2E8F0);

  // Primary Colors (Joyful Yellow from Logo)
  static const Color primary = Color(0xFFFFB300); // Deep Amber/Yellow
  static const Color onPrimary = Color(0xFF001946); // Dark Navy Blue for text on yellow buttons
  static const Color primaryContainer = Color(0xFFFFE082);
  static const Color onPrimaryContainer = Color(0xFF3E2D00);

  // Secondary Colors (Navy Blue from Logo text)
  static const Color secondary = Color(0xFF001946); // Navy Blue
  static const Color onSecondary = Colors.white;
  static const Color secondaryContainer = Color(0xFFD6E4FF);
  static const Color onSecondaryContainer = Color(0xFF001946);

  // Tertiary Colors (Vibrant Green)
  static const Color tertiary = Color(0xFF34A853);
  static const Color onTertiary = Colors.white;
  static const Color tertiaryContainer = Color(0xFFB9F6CA);
  static const Color onTertiaryContainer = Color(0xFF00210E);

  // Error Colors (Soft Red)
  static const Color error = Color(0xFFEA4335);
  static const Color onError = Colors.white;
  static const Color burgundy = Color(0xFF6B1A2A);

  // Background and Surface
  static const Color background = Color(0xFFF8FAFC); // Very light blue/grey
  static const Color onBackground = Color(0xFF1E1E1E);
  static const Color surface = Colors.white;
  static const Color onSurface = Color(0xFF1E1E1E);

  // Custom child-friendly colors
  static const Color pink = Color(0xFFD9A9B2);
  static const Color orange = Color(0xFFFF9800);
}
