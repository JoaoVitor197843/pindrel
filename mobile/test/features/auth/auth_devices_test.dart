import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/features/auth/data/server_trust.dart';
import 'package:mobile/features/auth/presentation/pages/auth_page.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';
import 'package:mobile/features/auth/presentation/widgets/server_dropdown_selector.dart';

import '../../support/discovery_fakes.dart';

/// Screen sizes in dp (logical pixels), from the manufacturers' own specifications; the ones marked ~ are rounded.
const devices = <(String, double, double)>[
  ('iPhone SE (1ª geração)', 320, 568),
  ('Galaxy Z Fold 5, tela externa ~', 344, 882),
  ('Galaxy S24', 360, 780),
  ('iPhone SE (3ª geração)', 375, 667),
  ('iPhone 13 mini', 375, 812),
  ('iPhone 15', 390, 844),
  ('Pixel 8', 412, 915),
  ('iPhone 15 Pro Max', 430, 932),
  ('Galaxy Z Fold 5, aberto ~', 673, 841),
  ('iPad mini', 744, 1133),
  ('Galaxy Tab S9', 800, 1280),
  ('iPad Pro 12,9"', 1024, 1366),
  ('Notebook 1366x768', 1366, 768),
  ('Janela padrão do Linux', 1280, 720),
  ('Monitor Full HD', 1920, 1080),
];

/// What the people who design touch screens ask of a tap target (Apple 44, Material 48): under 44 dp tall is too small.
const minTarget = 44.0;

void main() {
  final report = <String>[];
  tearDownAll(() {
    final out = Platform.environment['DEVICE_REPORT'];
    if (out != null) File(out).writeAsStringSync(report.join('\n'));
  });

  // portrait and landscape (a phone on its side is 568 dp wide and 320 tall: the desktop layout starts at 840 dp wide)
  final cases = [
    for (final (name, w, h) in devices) (name, w, h),
    for (final (name, w, h) in devices.where((d) => d.$2 < d.$3)) ('$name deitado', h, w),
  ];
  for (final (name, w, h) in cases) {
    for (final scale in [1.0, 1.3]) {
      for (final register in [false, true]) {
        final label = '$name (${w.toInt()}x${h.toInt()} dp), texto ${scale}x, ${register ? 'criar conta' : 'entrar'}';
        testWidgets(label, (tester) async {
          tester.view.physicalSize = Size(w * 2, h * 2);
          tester.view.devicePixelRatio = 2;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
          await tester.pumpWidget(ProviderScope(
            overrides: [
              serverDiscoveryProvider.overrideWithValue(FakeDiscovery(sampleServers)),
              keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
            ],
            child: const PindrelApp(home: AuthPage()),
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          if (register) {
            await tester.ensureVisible(find.byKey(const ValueKey('toggle-mode')));
            await tester.tap(find.byKey(const ValueKey('toggle-mode')));
            await tester.pump(const Duration(milliseconds: 400));
          }
          expect(tester.takeException(), isNull, reason: 'overflow');

          Size size(Finder f) => tester.getSize(f.first);
          Finder inkOf(String text) => find.ancestor(of: find.text(text), matching: find.byType(InkWell));
          final targets = <String, Size>{
            'campo e-mail': size(find.byKey(const Key('email-field'))),
            'campo senha': size(find.byKey(const Key('password-field'))),
            'botão principal': size(find.byType(FilledButton)),
            'botão offline': size(find.byType(OutlinedButton)),
            'trocar entrar/criar': size(find.byKey(const ValueKey('toggle-mode'))),
            'mostrar senha': size(inkOf(register ? 'MOSTRAR' : 'MOSTRAR')),
            'seletor de servidor': size(find.byType(ServerDropdownSelector)),
            if (!register) 'manter conectado': size(inkOf('Manter conectado')),
            if (!register) 'chave de recuperação': size(inkOf('Chave de recuperação')),
          };
          final small = targets.entries.where((e) => e.value.height < minTarget).map((e) => '${e.key} ${e.value.height.toStringAsFixed(0)}').toList();
          if (h < AuthPage.compactHeight && !register) {
            // a phone on its side: the form must start on the first screen, not behind a tall header
            expect(tester.getRect(find.byKey(const Key('email-field'))).bottom, lessThanOrEqualTo(h), reason: 'e-mail visível sem rolar em $name');
          }
          if (h < AuthPage.desktopMinHeight) expect(find.text('Roda no seu hardware'), findsNothing, reason: 'painel de desktop numa janela baixa');
          final primary = tester.getRect(find.byType(FilledButton));
          final fits = primary.bottom <= h;
          report.add('| $name | ${w.toInt()}x${h.toInt()} | ${scale}x | ${register ? 'criar' : 'entrar'} | ${fits ? 'sim' : 'rola'} | ${small.isEmpty ? 'ok' : small.join(', ')} |');
          expect(small, isEmpty, reason: 'alvos de toque abaixo de ${minTarget.toInt()} dp em $name');
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
