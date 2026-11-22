import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../notes/presentation/pages/account_gate.dart';
import '../../../notes/presentation/pages/notes_gate.dart';
import '../../data/auth_session.dart';
import '../providers/auth_provider.dart';
import 'auth_page.dart';

/// The app's first screen. A device that stayed signed in goes back to its account; otherwise this is the login, and
/// "Continuar offline" leads to the notes of the device. The check is instant when nothing was kept.
class StartGate extends ConsumerWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restored = ref.watch(sessionRestoreProvider);
    if (restored.isLoading) return const Scaffold(body: SizedBox.expand());
    final session = restored.value;
    // The restore result is kept for the life of the app, so it only counts while the session it found is still signed in:
    // after a sign-out (or a session the server ended) the cached value is stale and must not bring the account back.
    final live = ref.watch(authSessionProvider).status == AuthStatus.signedIn;
    if (session != null && live) return AccountGate(user: session.user, server: session.server);
    return AuthPage(onContinueOffline: () => _offline(context));
  }

  // replaces the login: "back" from the notes must not land on it
  static void _offline(BuildContext context) =>
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const NotesGate()));
}
