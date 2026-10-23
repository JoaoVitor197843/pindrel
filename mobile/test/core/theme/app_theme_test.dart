import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/theme/app_theme.dart';

void main() {
  test('paleta Editorial Dark do CLAUDE.md', () {
    expect(AppColors.background, const Color(0xFF141412));
    expect(AppColors.surface, const Color(0xFF1E1E1B));
    expect(AppColors.border, const Color(0xFF2E2E2A));
    expect(AppColors.text, const Color(0xFFEAE6DF));
    expect(AppColors.textMuted, const Color(0xFF9A968E));
    expect(AppColors.accent, const Color(0xFF4A5D44));
    expect(AppColors.accentBorder, const Color(0xFF6B8E61));
    expect(AppColors.primaryButton, const Color(0xFFF5F2EB));
    expect(AppColors.onPrimaryButton, const Color(0xFF141412));
  });

  test('o tema é escuro, sem Material 3 genérico nem sombras pesadas', () {
    final theme = AppTheme.dark;
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.cardTheme.elevation ?? 0, 0);
  });

  test('texto serif e mono usam fontes do sistema, sem pacote de fontes', () {
    expect(AppText.serif(24).fontFamily, 'serif');
    expect(AppText.serif(24).fontSize, 24);
    expect(AppText.mono(11).fontFamily, 'monospace');
  });
}
