import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Estilos de texto nativos (sem pacotes de fonte): serifa para títulos,
/// monoespaçada para badges e ações.
abstract final class AppText {
  static TextStyle serif(
    double size, {
    Color color = AppColors.text,
    FontStyle? fontStyle,
  }) => TextStyle(
    fontFamily: 'serif',
    fontSize: size,
    color: color,
    fontStyle: fontStyle,
    height: 1.2,
  );

  static TextStyle mono(
    double size, {
    Color color = AppColors.textMuted,
    double letterSpacing = 1.4,
  }) => TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
  );
}

abstract final class AppTheme {
  static const radius = 10.0;

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide(color: color),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: NoSplash.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accentBorder,
      onPrimary: AppColors.text,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    textTheme: Typography.material2021().white.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.accentBorder),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface,
      contentTextStyle: const TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}
