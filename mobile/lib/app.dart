import 'package:flutter/material.dart';

import 'core/performance/frame_pacer.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/pages/start_gate.dart';

class PindrelApp extends StatelessWidget {
  /// [home] lets a test start on another screen (the account screen, for one).
  const PindrelApp({super.key, this.home = const StartGate()});
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pindrel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      // "Energia > Economia" also stops decorative motion (entrances, pulsing dots), as the system's reduce-motion does
      builder: (context, child) => ValueListenableBuilder<PowerMode>(
        valueListenable: FramePacer.mode,
        child: child,
        builder: (context, mode, child) => mode == PowerMode.saving ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!) : child!,
      ),
      home: home,
    );
  }
}
