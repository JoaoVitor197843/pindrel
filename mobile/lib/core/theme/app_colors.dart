import 'package:flutter/painting.dart';

/// Pindrel's Editorial Dark Variant palette. The app's only source of colors.
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

  /// Text on accent fills and selected entries (4.9:1 there); `accentBorder` is only for borders and dots.
  static const accentText = Color(0xFF8FB085);

  /// The edge of a field or an outline button (3:1 against the background); `border` stays for dividers and cards.
  static const fieldBorder = Color(0xFF75716A);

  /// Earth red for what went offline (disconnected server).
  static const offline = Color(0xFFC4574A);

  /// Red as TEXT (4.5:1 on the background and surfaces).
  static const offlineText = Color(0xFFCD7065);

  static const primaryButton = Color(0xFFF5F2EB);
  static const onPrimaryButton = Color(0xFF141412);

  /// Tag colors (the web's `tag-*` tokens). `accent` reuses the moss green.
  static const tagRust = Color(0xFFD98A6C);
  static const tagBlue = Color(0xFF8AA8C4);
  static const tagTeal = Color(0xFF6BB3A8);
  static const tagGold = Color(0xFFD1AD5A);
  static const tagPlum = Color(0xFFC196AD);
}
