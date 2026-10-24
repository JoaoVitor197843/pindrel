import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'auth_header.dart';

/// Left panel of the desktop layout: brand, tagline, selling points and footer.
class AuthDesktopPanel extends StatelessWidget {
  /// On desktop there is room: the server name and the dot fit without ellipsis.
  static const desktopSelectorMaxWidth = 260.0;

  const AuthDesktopPanel({super.key, this.onAddServer});

  final VoidCallback? onAddServer;

  static const _features = [
    (
      'SELF-HOSTED',
      'Roda no seu hardware',
      'Nenhuma nota sai do seu servidor. Sem SaaS, sem telemetria, sem assinatura.',
    ),
    (
      'BLOCOS',
      'Blocos aninhados',
      'Páginas dentro de páginas, listas dentro de listas — a estrutura acompanha o pensamento.',
    ),
    (
      'COFRE',
      'Cofre com criptografia',
      'Marque uma página como cofre e ela é gravada cifrada, com chave derivada da sua senha.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthBrandAndServerRow(
            onAddServer: onAddServer,
            maxSelectorWidth: desktopSelectorMaxWidth,
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _buildPitch(),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              Text('plany v0.9.5', style: AppText.mono(12, letterSpacing: 0.4)),
              Text('•', style: AppText.mono(12, letterSpacing: 0.4)),
              Text(
                'licença AGPL-3.0',
                style: AppText.mono(12, letterSpacing: 0.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: AppText.serif(44),
            children: [
              const TextSpan(text: 'Suas notas.\n'),
              TextSpan(
                text: 'Seu servidor.',
                style: AppText.serif(
                  44,
                  color: AppColors.accentBorder,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Um espaço de escrita para você e sua família, rodando na sua '
          'própria máquina — sem contas na nuvem de ninguém.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        for (final (tag, title, body) in _features) _Feature(tag, title, body),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.tag, this.title, this.body);

  final String tag;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                tag,
                style: AppText.mono(11, color: AppColors.accentBorder),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.45,
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
