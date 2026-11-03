import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';

/// The person of these tests: picks the first server of the list (the app chooses nothing on its own).
Future<void> chooseFirst(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));
  final controller = container.read(serverListControllerProvider);
  // the list arrives after what was remembered is read: give it a few turns
  for (var i = 0; i < 10 && controller.current.available.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (controller.current.available.isEmpty || controller.current.selected != null) return;
  await controller.select(controller.current.available.first);
  await tester.pump();
}
