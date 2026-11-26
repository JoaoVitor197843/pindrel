import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/auth_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_session.dart';
import '../../../auth/presentation/pages/start_gate.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/notes_provider.dart';
import 'dashboard_page.dart';

/// The notes of a signed-in account (their own database). There is no sync yet: signing in only opens the account's
/// space, as on the web. When the server ends the session (the renewal is refused) the person goes back to the notes of
/// the device with a note about it.
class AccountGate extends ConsumerStatefulWidget {
  const AccountGate({super.key, required this.user, required this.server});

  final Account user;
  final Uri server;

  @override
  ConsumerState<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends ConsumerState<AccountGate> {
  late final AuthSession _session = ref.read(authSessionProvider);
  var _leaving = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (_leaving || _session.status != AuthStatus.out || !mounted) return;
    // a screen that is no longer on top (erasing the device signs out under its "Apagando..." screen) does not navigate
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _leave(message: _session.endedByServer ? 'Sua sessão terminou. Entre de novo.' : null);
  }

  void _logout() {
    _leaving = true; // a deliberate sign-out is not "the session ended"
    // The device is signed out the moment logout() is called (before its first await); what is left is telling the server,
    // which may be slow or gone and must never keep the person on this screen.
    unawaited(_session.logout());
    _leave();
  }

  void _leave({String? message}) {
    _leaving = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const StartGate()), (_) => false);
    if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(accountWorkspaceProvider(widget.user.id));
    return ws.when(
      data: (w) => DashboardPage(
        ws: w,
        userName: widget.user.username,
        email: widget.user.email,
        server: widget.server.authority,
        onLogout: _logout,
      ),
      loading: () => const Scaffold(body: SizedBox.expand()),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Não foi possível abrir as notas da conta', style: AppText.serif(22), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('$e', style: const TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _logout, child: const Text('Sair da conta')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
