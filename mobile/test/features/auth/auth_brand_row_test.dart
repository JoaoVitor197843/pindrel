import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/pairing.dart';
import 'package:mobile/features/auth/data/server_trust.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';
import 'package:mobile/features/auth/presentation/widgets/auth_header.dart';
import 'package:mobile/features/auth/presentation/widgets/pulsing_dot.dart';
import 'package:mobile/features/auth/presentation/widgets/server_dropdown_selector.dart';

import '../../support/choose_first.dart';
import '../../support/discovery_fakes.dart';

void main() {
  group('selectorWidthFor', () {
    const brand = AuthBrandRow.minWidth;
    const gap = AuthBrandAndServerRow.gap;

    test('com espaço de sobra, o botão vai até o máximo pedido', () {
      expect(AuthBrandAndServerRow.selectorWidthFor(500, 156), 156);
      expect(AuthBrandAndServerRow.selectorWidthFor(900, 260), 260);
    });

    test('sem espaço, o botão fica só com o que sobra depois da marca', () {
      expect(
        AuthBrandAndServerRow.selectorWidthFor(brand + gap + 120, 156),
        120,
      );
    });

    test('nunca fica menor que o mínimo útil, nem maior que o máximo', () {
      expect(
        AuthBrandAndServerRow.selectorWidthFor(10, 156),
        AuthBrandAndServerRow.minSelectorWidth,
      );
      expect(
        AuthBrandAndServerRow.selectorWidthFor(brand + gap + 400, 156),
        156,
      );
    });
  });

  group('AuthBrandAndServerRow', () {
    Future<double> selectorWidth(
      WidgetTester tester, {
      required double rowWidth,
      double? max,
      double textScale = 1.0,
    }) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverTrustProvider.overrideWithValue(
              ServerTrust(MemoryKeyValueStore()),
            ),
            pairedStoreProvider.overrideWithValue(MemoryPairedStore()),
            serverDiscoveryProvider.overrideWithValue(
              FakeDiscovery([
                server(
                  'Servidor da Sala de Estar da Casa de Praia',
                  addresses: ['10.0.0.1'],
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: rowWidth,
                  child: max == null
                      ? const AuthBrandAndServerRow()
                      : AuthBrandAndServerRow(maxSelectorWidth: max),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await chooseFirst(tester);
      return tester
          .getSize(
            find
                .ancestor(
                  of: find.byType(PulsingDot),
                  matching: find.byType(Container),
                )
                .first,
          )
          .width;
    }

    testWidgets('no celular o botão não passa do máximo do celular', (
      tester,
    ) async {
      final w = await selectorWidth(tester, rowWidth: 420);
      expect(w, ServerDropdownSelector.defaultMaxWidth);
      expect(tester.takeException(), isNull);
    });

    // The brand used to be given a fixed 132 px, which a 320 dp Android emulator proved too little for the real serif font
    // ("RenderFlex overflowed by 9.7 pixels" on the login screen). It is measured now, so whenever the row has room for the
    // brand plus the smallest button, nothing may overflow, at any system text size.
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'com a fonte do sistema a ${scale}x a marca nunca estoura quando cabe',
        (tester) async {
          final probe = GlobalKey();
          late double needed;
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  needed = AuthBrandRow.neededWidth(context);
                  return SizedBox(key: probe);
                },
              ),
            ),
          );
          expect(needed, greaterThanOrEqualTo(AuthBrandRow.minWidth));
          final enough =
              needed +
              AuthBrandAndServerRow.gap +
              AuthBrandAndServerRow.minSelectorWidth;
          for (final extra in [0.0, 1.0, 40.0, 300.0]) {
            await selectorWidth(
              tester,
              rowWidth: enough + extra,
              textScale: scale,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'linha de ${enough + extra} px, fonte ${scale}x',
            );
          }
        },
      );
    }

    testWidgets('um texto maior reserva mais espaço para a marca', (
      tester,
    ) async {
      late double normal, big;
      Widget probe(double scale, void Function(double) set) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            set(AuthBrandRow.neededWidth(context));
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(probe(1.0, (v) => normal = v));
      await tester.pumpWidget(probe(2.0, (v) => big = v));
      expect(big, greaterThan(normal));
    });

    testWidgets('no desktop o botão pode ser bem mais largo', (tester) async {
      final w = await selectorWidth(tester, rowWidth: 700, max: 260);
      expect(w, greaterThan(ServerDropdownSelector.defaultMaxWidth));
      expect(w, lessThanOrEqualTo(260));
      expect(tester.takeException(), isNull);
    });
  });
}
