import 'package:appflowy_editor/appflowy_editor.dart' show RowBudget;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_restart.dart';
import 'core/performance/frame_pacer.dart';

void main() {
  PindrelBinding.ensureInitialized();
  FramePacer.watch();
  FramePacer.mode.addListener(() => RowBudget.saving = FramePacer.saving);
  runApp(const AppRestart(child: ProviderScope(child: PindrelApp())));
}
