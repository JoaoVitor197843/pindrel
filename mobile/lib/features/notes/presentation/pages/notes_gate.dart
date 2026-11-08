import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/notes_provider.dart';
import 'dashboard_page.dart';

/// Opens the notes database, then shows the dashboard. The app works with no
/// server: the account screen is one step away, never in the way.
class NotesGate extends ConsumerWidget {
  const NotesGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    return ws.when(
      data: (w) => DashboardPage(ws: w),
      loading: () => const Scaffold(body: SizedBox.expand()),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Não foi possível abrir suas notas', style: AppText.serif(22), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('$e', style: const TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => ref.invalidate(workspaceProvider), child: const Text('Tentar de novo')),
            ]),
          ),
        ),
      ),
    );
  }
}
