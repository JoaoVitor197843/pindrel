import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/notes/presentation/pages/notes_gate.dart';

class PindrelApp extends StatelessWidget {
  /// [home] lets a test start on another screen (the account screen, for one).
  const PindrelApp({super.key, this.home = const NotesGate()});
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pindrel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: home,
    );
  }
}
