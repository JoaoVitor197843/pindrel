import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

/// Simple recovery modal by code (recovery key).
class RecoveryKeySheet extends StatelessWidget {
  const RecoveryKeySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (_) => const RecoveryKeySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chave de recuperação', style: AppText.serif(24)),
          const SizedBox(height: 8),
          const Text(
            'Digite o código de recuperação gerado quando você criou a conta.',
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            style: AppText.mono(14, color: AppColors.text, letterSpacing: 2),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryButton,
                foregroundColor: AppColors.onPrimaryButton,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Recuperar acesso'),
            ),
          ),
        ],
      ),
    );
  }
}
