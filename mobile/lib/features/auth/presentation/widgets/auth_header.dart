import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'server_dropdown_selector.dart';

/// Cabeçalho escuro com marca, tag SELF-HOSTED, seletor de servidor e slogan.
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
          Row(
            children: [
              const Expanded(child: AuthBrandRow()),
              const SizedBox(width: 8),
              ServerDropdownSelector(onAddServer: onAddServer),
            ],
          ),
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

/// Marca `P`, nome e tag SELF-HOSTED.
class AuthBrandRow extends StatelessWidget {
  const AuthBrandRow({super.key});

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
