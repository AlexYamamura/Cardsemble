import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF244A3A);
  static const Color primaryDark = Color(0xFF173F35);
  static const Color cream = Color(0xFFF3EFE6);
  static const Color sand = Color(0xFFD8CDBB);
  static const Color charcoal = Color(0xFF292D29);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF3EFE6);
  static const Color error = Color(0xFFB00020);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF292D29);
  static const Color onBackground = Color(0xFF292D29);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFD8CDBB);
  static const Color outlineVariant = Color(0xFFE8E0D8);

  static const Color success = Colors.green;
  static const Color warning = Colors.orange;
  static const Color info = Colors.blue;

  static const Color greenConnected = Colors.green;
  static const Color orangePending = Colors.orange;
  static const Color redError = Colors.red;
  static const Color greyDisabled = Colors.grey;
}

extension AppColorsScheme on ColorScheme {
  Color get appPrimary => AppColors.primary;
  Color get appPrimaryDark => AppColors.primaryDark;
  Color get appCream => AppColors.cream;
  Color get appSand => AppColors.sand;
  Color get appCharcoal => AppColors.charcoal;
}