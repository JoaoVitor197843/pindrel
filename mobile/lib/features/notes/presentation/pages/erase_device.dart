import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_restart.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/pages/start_gate.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/notes_provider.dart';

/// Signs out, closes the databases, erases what the app keeps on this device and starts the app over at the login.
/// The screen is replaced first, so nothing is still showing (or writing) the notes that are being deleted.
Future<void> eraseThisDevice(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const _Message(working: true)), (_) => false);
  await WidgetsBinding.instance.endOfFrame;
  try {
    // the server may be slow or gone: the device is signed out at once, telling the server must not hold this up
    await container.read(authSessionProvider).logout().timeout(const Duration(seconds: 3), onTimeout: () {});
    container.invalidate(workspaceProvider); // closes the database of the device's notes
    await Future<void>.delayed(const Duration(milliseconds: 50)); // and the ones of accounts, whose screen is gone
    await container.read(deviceDataProvider).erase();
  } catch (e) {
    if (navigator.mounted) {
      unawaited(navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (c) => _Message(error: '$e', onDone: () => _restart(navigator))),
        (_) => false,
      ));
    }
    return;
  }
  if (navigator.mounted) _restart(navigator);
}

void _restart(NavigatorState navigator) {
  if (!AppRestart.restart(navigator.context)) {
    // no root to restart (tests): the login is where a restart would end up
    navigator.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const StartGate()), (_) => false);
  }
}

class _Message extends StatelessWidget {
  const _Message({this.working = false, this.error, this.onDone});
  final bool working;
  final String? error;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (working) ...[
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(height: 16),
              Text('Apagando os dados deste aparelho...', style: AppText.serif(20), textAlign: TextAlign.center),
            ] else ...[
              Text('Não foi possível apagar tudo', style: AppText.serif(22), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(error ?? '', style: const TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onDone, child: const Text('Voltar ao início')),
            ],
          ],
        ),
      ),
    ),
  );
}
