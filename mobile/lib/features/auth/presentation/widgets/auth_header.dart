import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'logo_mark.dart';
import 'server_dropdown_selector.dart';

/// Dark header with brand, SELF-HOSTED tag, server selector and tagline.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.onAddServer});

  final VoidCallback? onAddServer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.paddingOf(context).top + 16,
        24,
        28,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthBrandAndServerRow(onAddServer: onAddServer),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              style: AppText.serif(20),
              children: [
                const TextSpan(text: 'Suas notas. '),
                TextSpan(
                  text: 'Seu servidor.',
                  style: AppText.serif(
                    20,
                    color: AppColors.accentBorder,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The brand on the left and the server selector on the right. The brand has priority:
/// the server button gets the space that is left (up to [maxSelectorWidth]), and
/// the name inside it gets an ellipsis if it does not fit.
class AuthBrandAndServerRow extends StatelessWidget {
  const AuthBrandAndServerRow({
    super.key,
    this.onAddServer,
    this.maxSelectorWidth = ServerDropdownSelector.defaultMaxWidth,
  });

  final VoidCallback? onAddServer;
  final double maxSelectorWidth;

  static const gap = 8.0;

  /// Smallest useful width of the button (dot, a piece of the name and the arrow).
  static const minSelectorWidth = 96.0;

  /// Width of the button in a row of [rowWidth]: what is left after the brand ([brandWidth], at least
  /// [AuthBrandRow.minWidth]), between [minSelectorWidth] and [maxSelectorWidth].
  static double selectorWidthFor(
    double rowWidth,
    double maxSelectorWidth, [
    double brandWidth = AuthBrandRow.minWidth,
  ]) =>
      (rowWidth -
              gap -
              (brandWidth < AuthBrandRow.minWidth
                  ? AuthBrandRow.minWidth
                  : brandWidth))
          .clamp(minSelectorWidth, maxSelectorWidth)
          .toDouble();

  @override
  Widget build(BuildContext context) {
    // The brand's own width depends on the font the system really draws ("Pindrel" in the Android serif is not as wide as in
    // the font the widget tests use), so it is measured, not assumed: a constant was 9.7 px short on a 320 dp emulator.
    final brand = AuthBrandRow.neededWidth(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            const Expanded(child: AuthBrandRow()),
            const SizedBox(width: gap),
            ServerDropdownSelector(
              onAddServer: onAddServer,
              maxWidth: selectorWidthFor(
                constraints.maxWidth,
                maxSelectorWidth,
                brand,
              ),
            ),
          ],
        );
      },
    );
  }
}

class AuthBrandRow extends StatelessWidget {
  const AuthBrandRow({super.key});

  /// Smallest width the brand is given when nothing is measured (a floor, never less).
  static const minWidth = 132.0;

  static const _logo = 36.0;
  static const _gap = 10.0;

  /// What is left of the tag when it has shrunk as far as it goes: padding (12), border (2) and an ellipsis (~6), with a margin.
  static const _tagFloor = 24.0;

  static const _nameSize = 24.0;

  /// Width the brand needs to show the logo and the whole name with the tag shrunk to its floor, for the font and the text
  /// scale the system really uses.
  static double neededWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Pindrel', style: AppText.serif(_nameSize)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final name = painter.width;
    painter.dispose();
    return _logo + _gap + name + _gap + _tagFloor;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const LogoMark(),
        const SizedBox(width: _gap),
        Text('Pindrel', style: AppText.serif(_nameSize)),
        const SizedBox(width: _gap),
        const Flexible(child: _Tag('SELF-HOSTED')),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.mono(9, letterSpacing: 1.2),
      ),
    );
  }
}
