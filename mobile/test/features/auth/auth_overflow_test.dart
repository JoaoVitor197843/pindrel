import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/features/auth/data/server_trust.dart';
import 'package:mobile/features/auth/presentation/pages/auth_page.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';

import '../../support/discovery_fakes.dart';

/// The login screen must never overflow, whatever the window and the text size (the brand and the server button used to
/// share one row even when they could not both fit). The widget tests' font is wider than a real one, so what fits here
/// fits on a device.
void main() {
  for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0), (360.0, 2.0), (450.0, 2.0), (450.0, 3.0), (840.0, 2.0), (1000.0, 2.0), (1400.0, 2.0)]) {
    for (final servers in [true, false]) {
      testWidgets('${width.toInt()} dp, text ${scale}x, ${servers ? 'with' : 'without'} servers: no overflow', (tester) async {
        tester.view.physicalSize = Size(width * 2, 1800);
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              serverDiscoveryProvider.overrideWithValue(FakeDiscovery(servers ? sampleServers : const [])),
              keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
            ],
            child: const PindrelApp(home: AuthPage()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
