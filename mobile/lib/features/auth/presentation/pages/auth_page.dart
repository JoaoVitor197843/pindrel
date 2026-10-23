import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/server_list_state.dart';
import '../providers/servers_provider.dart';
import '../widgets/auth_desktop_panel.dart';
import '../widgets/auth_form.dart';
import '../widgets/auth_header.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/server_dropdown_selector.dart';

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

/// Rodapé do desktop: o endereço do servidor escolhido e se ele está na rede.
class _ServerFooter extends ConsumerWidget {
  const _ServerFooter();

  static const _fontSize = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(serverListControllerProvider);
    return StreamBuilder<ServerListState>(
      initialData: controller.current,
      stream: controller.stream,
      builder: (context, snapshot) {
        final state = snapshot.requireData;
        final server = state.selected;
        final text = switch (state.connection) {
          ServerConnection.none => '→ Procurando servidores na rede...',
          ServerConnection.connected => '→ Rodando em: ${server!.address}',
          ServerConnection.disconnected =>
            '→ Desconectado de: ${server!.address}',
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (server != null) ...[
                PulsingDot(
                  key: const ValueKey('server-footer-dot'),
                  color: connectionColor(state.connection),
                  diameter: dotDiameterFor(_fontSize),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(_fontSize, letterSpacing: 0.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
