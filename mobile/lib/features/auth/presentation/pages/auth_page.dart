import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/servers_provider.dart';
import '../widgets/auth_desktop_panel.dart';
import '../widgets/auth_form.dart';
import '../widgets/auth_header.dart';

/// Tela de login / cadastro com layout adaptativo: cabeçalho + formulário em
/// telas estreitas, painel institucional + formulário lado a lado em largas.
class AuthPage extends StatelessWidget {
  const AuthPage({super.key, this.onContinueOffline});

  /// Largura mínima (em dp) para usar o layout desktop.
  static const desktopBreakpoint = 840.0;

  /// Chamado ao tocar em "Continuar offline neste dispositivo".
  final VoidCallback? onContinueOffline;

  static void _showAddServerSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adicionar servidor chega em breve.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          void addServer() => _showAddServerSoon(context);
          if (constraints.maxWidth >= desktopBreakpoint) {
            return _DesktopLayout(
              onContinueOffline: onContinueOffline,
              onAddServer: addServer,
            );
          }
          return _MobileLayout(
            onContinueOffline: onContinueOffline,
            onAddServer: addServer,
          );
        },
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({this.onContinueOffline, required this.onAddServer});

  final VoidCallback? onContinueOffline;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AuthHeader(onAddServer: onAddServer),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AuthForm(onContinueOffline: onContinueOffline),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({this.onContinueOffline, required this.onAddServer});

  final VoidCallback? onContinueOffline;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 11,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: AuthDesktopPanel(onAddServer: onAddServer),
          ),
        ),
        Expanded(
          flex: 12,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: AuthForm(
                        showSubtitle: true,
                        onContinueOffline: onContinueOffline,
                      ),
                    ),
                  ),
                ),
              ),
              const _ServerFooter(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerFooter extends ConsumerWidget {
  const _ServerFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(selectedServerProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Text(
        '→ Rodando em: ${server.address}',
        style: AppText.mono(12, letterSpacing: 0.6),
      ),
    );
  }
}
