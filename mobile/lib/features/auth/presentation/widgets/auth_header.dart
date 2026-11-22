import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'logo_mark.dart';
import 'server_dropdown_selector.dart';

/// Dark header with brand, SELF-HOSTED tag, server selector and tagline.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.onAddServer, this.compact = false});

  final VoidCallback? onAddServer;

  /// A window too short for the tagline (a phone on its side): brand and server button only.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.paddingOf(context).top + (compact ? 10 : 16),
        24,
        compact ? 12 : 28,
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
          if (!compact) ...[
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

  /// Width at which the button shows its whole label ("1 DISPONÍVEL"); a row that cannot give it this much puts the
  /// button under the brand instead of cutting it.
  static const comfortSelectorWidth = 150.0;

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
        final needed =
            (brand < AuthBrandRow.minWidth ? AuthBrandRow.minWidth : brand) +
            gap +
            comfortSelectorWidth;
        if (constraints.maxWidth < needed) {
          // Brand and a usable button do not fit side by side (a narrow window with large text): the button goes under
          // the brand, as wide as the row allows, instead of the row overflowing.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AuthBrandRow(),
              const SizedBox(height: 12),
              ServerDropdownSelector(
                onAddServer: onAddServer,
                maxWidth: constraints.maxWidth
                    .clamp(0.0, maxSelectorWidth)
                    .toDouble(),
              ),
            ],
          );
        }
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

  /// What is left of the tag when it has shrunk as far as it goes: padding (12), border (2) and a few letters with an ellipsis, so it never shows as an empty box.
  static const _tagFloor = 24.0;

  /// Room the whole tag needs (a cut "SELF-HOST…" looks careless); with less it is left out.
  static const tagMinWidth = 88.0;

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
    // The name takes what it needs (an ellipsis only when even the logo leaves it less). The tag is decoration: it shows
    // when there is room for letters, and is left out otherwise (an empty or one-letter box says nothing). Two Flexibles
    // would have split the free room in halves and cut the name while the tag still had room.
    return LayoutBuilder(
      builder: (context, constraints) {
        final nameBox = (constraints.maxWidth - _logo - _gap)
            .clamp(0.0, double.infinity)
            .toDouble();
        final painter = TextPainter(
          text: TextSpan(text: 'Pindrel', style: AppText.serif(_nameSize)),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final nameWidth = painter.width.clamp(0.0, nameBox).toDouble();
        painter.dispose();
        final tagRoomLeft = nameBox - nameWidth - _gap;
        return Row(
          children: [
            const LogoMark(),
            const SizedBox(width: _gap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: nameBox),
              child: Text(
                'Pindrel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.serif(_nameSize),
              ),
            ),
            if (tagRoomLeft >= tagMinWidth) ...[
              const SizedBox(width: _gap),
              const Flexible(child: _Tag('SELF-HOSTED')),
            ],
          ],
        );
      },
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
