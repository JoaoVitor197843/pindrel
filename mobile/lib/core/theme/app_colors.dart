import 'package:flutter/painting.dart';

/// Plany's Editorial Dark Variant palette. The app's only source of colors.
abstract final class AppColors {
  static const background = Color(0xFF141412);
  static const surface = Color(0xFF1E1E1B);
  static const border = Color(0xFF2E2E2A);

  static const text = Color(0xFFEAE6DF);
  static const textMuted = Color(0xFF9A968E);

  /// Moss green: `accent` for fills, `accentBorder` for border/active text.
  static const accent = Color(0xFF4A5D44);
  static const accentBorder = Color(0xFF6B8E61);
  static const accentSoft = Color(0x734A5D44);

  /// Earth red for what went offline (disconnected server).
  static const offline = Color(0xFFC4574A);

  static const primaryButton = Color(0xFFF5F2EB);
  static const onPrimaryButton = Color(0xFF141412);
}
