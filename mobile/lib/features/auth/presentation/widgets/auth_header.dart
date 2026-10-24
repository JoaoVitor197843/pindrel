import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
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

  /// Width of the button in a row of [rowWidth]: what is left after the brand,
  /// between [minSelectorWidth] and [maxSelectorWidth].
  static double selectorWidthFor(double rowWidth, double maxSelectorWidth) =>
      (rowWidth - gap - AuthBrandRow.minWidth)
          .clamp(minSelectorWidth, maxSelectorWidth)
          .toDouble();

  @override
  Widget build(BuildContext context) {
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

  /// Width of the brand and the name, without the tag (which shrinks with an ellipsis).
  static const minWidth = 132.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _BrandMark(),
        const SizedBox(width: 10),
        Text('Plany', style: AppText.serif(24)),
        const SizedBox(width: 10),
        const Flexible(child: _Tag('SELF-HOSTED')),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('P', style: AppText.serif(20)),
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
