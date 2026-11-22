import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/api/auth_api.dart';
import '../../../notes/presentation/pages/account_gate.dart';
import '../../data/server_list_state.dart';
import '../providers/auth_provider.dart';
import '../providers/servers_provider.dart';
import '../widgets/auth_desktop_panel.dart';
import '../widgets/auth_form.dart';
import '../widgets/auth_header.dart';
import '../widgets/pairing_dialogs.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/server_dropdown_selector.dart';

/// Login / sign-up screen with an adaptive layout: header + form on
/// narrow screens, institutional panel + form side by side on wide ones.
class AuthPage extends StatelessWidget {
  const AuthPage({super.key, this.onContinueOffline});

  /// Minimum width (in dp) to use the desktop layout.
  static const desktopBreakpoint = 840.0;

  /// ...and the least height: a phone on its side is wide enough but only 300-430 dp tall, too little for the panel and
  /// its footer, so it gets the single column.
  static const desktopMinHeight = 520.0;

  /// Below this height the header drops its tagline and scrolls away with the form.
  static const compactHeight = 480.0;

  /// Called when tapping "Continuar offline neste dispositivo".
  final VoidCallback? onContinueOffline;

  /// Signed in: the account's notes replace every screen (going "back" must not land on the login again).
  static void _enter(BuildContext context, Account user) {
    final server = ProviderScope.containerOf(context).read(authSessionProvider).server;
    if (server == null) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => AccountGate(user: user, server: server)),
      (_) => false,
    );
  }

  static void _showAddServer(BuildContext context) {
    unawaited(AddServerDialog.show(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          void addServer() => _showAddServer(context);
          void signedIn(Account user) => _enter(context, user);
          if (constraints.maxWidth >= desktopBreakpoint && constraints.maxHeight >= desktopMinHeight) {
            return _DesktopLayout(
              onContinueOffline: onContinueOffline,
              onSignedIn: signedIn,
              onAddServer: addServer,
            );
          }
          return _MobileLayout(
            onContinueOffline: onContinueOffline,
            onSignedIn: signedIn,
            onAddServer: addServer,
          );
        },
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({this.onContinueOffline, this.onSignedIn, required this.onAddServer});

  final VoidCallback? onContinueOffline;
  final void Function(Account)? onSignedIn;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < AuthPage.compactHeight;
    if (compact) {
      // the whole page scrolls, so the form gets the screen once the header is out of the way
      return SingleChildScrollView(
        child: Column(
          children: [
            AuthHeader(onAddServer: onAddServer, compact: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AuthForm(onContinueOffline: onContinueOffline, onSignedIn: onSignedIn),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        AuthHeader(onAddServer: onAddServer),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AuthForm(onContinueOffline: onContinueOffline, onSignedIn: onSignedIn),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({this.onContinueOffline, this.onSignedIn, required this.onAddServer});

  final VoidCallback? onContinueOffline;
  final void Function(Account)? onSignedIn;
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
                        onSignedIn: onSignedIn,
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

/// Desktop footer: the chosen server's address and whether it is on the network.
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
