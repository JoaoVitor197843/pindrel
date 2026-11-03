import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/network/pairing.dart';
import 'package:mobile/core/network/server_security.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/data/server_trust.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';
import 'package:mobile/features/auth/presentation/widgets/pairing_dialogs.dart';

import '../../support/discovery_fakes.dart';
import '../../support/pairing_fakes.dart';

/// Opens the app with the sample servers, none of them opened before, and the pairing replaced by a fake.
Future<ProviderContainer> pump(
  WidgetTester tester, {
  MemoryPairedStore? store,
  FakePairer? pairer,
  bool tls = true,
  ServerTrust? trust,
  double width = 450,
}) async {
  tester.view.physicalSize = Size(width * 2, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serverTrustProvider.overrideWithValue(trust ?? ServerTrust(MemoryKeyValueStore())),
        pairedStoreProvider.overrideWithValue(store ?? MemoryPairedStore()),
        serverDiscoveryProvider.overrideWithValue(FakeDiscovery(sampleServers)),
        serverProbeProvider.overrideWithValue((_) async => true),
        digitsPairerProvider.overrideWithValue((pairer ?? FakePairer(['123456'])).call),
        tlsOfferProvider.overrideWithValue((_) async => tls ? const TlsOffer(port: 8443) : null),
      ],
      child: const PindrelApp(),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Selecionar servidor'));
  await tester.pumpAndSettle();
}

void main() {
  group('lista sem escolha automática', () {
    testWidgets('o botão conta os servidores e nada é escolhido sozinho', (tester) async {
      final c = await pump(tester);
      expect(find.text('3 DISPONÍVEIS'), findsOneWidget);
      expect(c.read(serverListControllerProvider).current.selected, isNull);
      expect(find.text('CASA'), findsNothing);
    });

    testWidgets('o menu mostra a contagem e quem é confiável e quem precisa parear', (tester) async {
      final trust = ServerTrust(MemoryKeyValueStore());
      await trust.remember('Casa', '');
      await pump(tester, trust: trust);
      await openMenu(tester);
      expect(find.text('DISPONÍVEIS (3)'), findsOneWidget);
      expect(find.byKey(const ValueKey('server-badge-casa')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('server-item-casa')), matching: find.text('CONFIÁVEL')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('server-item-nuvem')), matching: find.text('PAREAR')), findsOneWidget);
    });
  });

  group('parear um servidor da rede', () {
    testWidgets('mostra os 6 números e o tempo, e "São iguais" escolhe o servidor e o torna confiável', (tester) async {
      final c = await pump(tester, pairer: FakePairer(['123456'], name: 'Nuvem'));
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-nuvem')));
      await tester.pumpAndSettle();

      expect(find.text('Parear com Nuvem'), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-digits')), findsOneWidget);
      expect(find.text('123 456'), findsOneWidget);
      expect(find.textContaining('Novos números em'), findsOneWidget);
      expect(find.text('São iguais'), findsOneWidget);
      expect(c.read(serverListControllerProvider).current.selected, isNull, reason: 'not chosen before the person confirms');

      await tester.tap(find.text('São iguais'));
      await tester.pumpAndSettle();
      expect(find.text('Parear com Nuvem'), findsNothing);
      final state = c.read(serverListControllerProvider).current;
      expect(state.selected?.name, 'Nuvem');
      expect(state.selected?.trusted, isTrue);
      expect(state.selected?.baseUri?.scheme, 'https', reason: 'from now on it is reached over HTTPS');
      expect(find.text('NUVEM'), findsOneWidget);
    });

    testWidgets('depois de parear um, outro servidor novo também pergunta', (tester) async {
      await pump(tester, pairer: FakePairer(['123456'], name: 'Nuvem'));
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-nuvem')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('São iguais'));
      await tester.pumpAndSettle();
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();
      expect(find.text('Parear com Casa'), findsOneWidget, reason: 'another new server asks');
    });

    testWidgets('Cancelar não escolhe nem guarda nada', (tester) async {
      final c = await pump(tester);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Parear com Casa'), findsNothing);
      expect(c.read(serverListControllerProvider).current.selected, isNull);
      expect(find.text('3 DISPONÍVEIS'), findsOneWidget);
    });

    testWidgets('passado o minuto, os números mudam e os velhos não voltam', (tester) async {
      await pump(tester, pairer: FakePairer(['111111', '222222', '333333']));
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('111 111'), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('111 111'), findsNothing);
      expect(find.text('222 222'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('fechar a tela no meio solta a sessão sem erro', (tester) async {
      await pump(tester);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(seconds: 120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('servidor sem HTTPS: avisa e deixa usar sem criptografia, se a pessoa quiser', (tester) async {
      final c = await pump(tester, tls: false);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();
      expect(find.textContaining('não oferece conexão segura'), findsOneWidget);
      await tester.tap(find.text('Usar sem criptografia'));
      await tester.pumpAndSettle();
      expect(c.read(serverListControllerProvider).current.selected?.name, 'Casa');
    });

    testWidgets('falhas do servidor são explicadas em palavras simples', (tester) async {
      for (final (reason, text) in [
        (PairingFailure.busy, 'Outro aparelho está pareando'),
        (PairingFailure.locked, 'tentativas demais'),
        (PairingFailure.unreachable, 'firewall'),
        (PairingFailure.declined, 'desconfie'),
        (PairingFailure.protocol, 'inesperado'),
      ]) {
        final c = await pump(tester, pairer: FakePairer(['123456'], result: PairingFailed(reason)));
        await openMenu(tester);
        await tester.tap(find.byKey(const ValueKey('server-item-casa')));
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget, reason: '$reason');
        expect(c.read(serverListControllerProvider).current.selected, isNull);
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('os números têm descrição para leitor de tela, dígito a dígito', (tester) async {
      await pump(tester);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Número de conferência: 1 2 3 4 5 6'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });

  group('adicionar servidor (código obrigatório)', () {
    Future<void> openAdd(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('+ Adicionar servidor...'));
      await tester.pumpAndSettle();
    }

    Finder codeField() => find.byKey(const ValueKey('pairing-code-field'));
    Finder addressField() => find.widgetWithText(TextField, AddServerDialog.addressLabel);
    bool codeEnabled(WidgetTester tester) => tester.widget<TextField>(codeField()).enabled ?? true;

    testWidgets('o nome é opcional: vazio usa o do servidor; digitado, é o que aparece, e é guardado', (tester) async {
      final store = MemoryPairedStore();
      final c = await pump(tester, pairer: FakePairer(['123456'], name: 'Raspberry'), store: store);
      await openAdd(tester);
      expect(find.text(AddServerDialog.nameLabel), findsOneWidget);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.enterText(find.byKey(const ValueKey('server-name-field')), '  Casa   da\tpraia \n');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('found-server')), findsOneWidget);
      expect(find.textContaining('Raspberry'), findsWidgets, reason: 'the server\'s own name is shown before confirming');
      await tester.enterText(codeField(), '123456');
      await tester.pump();
      await tester.tap(find.text('Parear'));
      await tester.pumpAndSettle();
      final selected = c.read(serverListControllerProvider).current.selected!;
      expect(selected.name, 'Casa da praia', reason: 'cleaned up: squeezed spaces, no tabs or breaks');
      expect(selected.trustName, 'Raspberry', reason: 'remembered by the server\'s own name');
      expect((await store.all()).single.label, 'Casa da praia');
      expect(find.text('CASA DA PRAIA'), findsOneWidget);
    });

    testWidgets('sem nome digitado, fica o nome que o servidor informa', (tester) async {
      final c = await pump(tester, pairer: FakePairer(['123456'], name: 'Raspberry'));
      await openAdd(tester);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();
      await tester.enterText(codeField(), '123456');
      await tester.pump();
      await tester.tap(find.text('Parear'));
      await tester.pumpAndSettle();
      expect(c.read(serverListControllerProvider).current.selected!.name, 'Raspberry');
    });

    testWidgets('o nome não pode passar de 64 caracteres, e some com espaços só', (tester) async {
      await pump(tester);
      await openAdd(tester);
      await tester.enterText(find.byKey(const ValueKey('server-name-field')), 'x' * 200);
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('server-name-field'))).controller!.text.length, 64);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('endereço inválido é recusado com uma dica, sem buscar nada', (tester) async {
      final pairer = FakePairer(['123456']);
      await pump(tester, pairer: pairer);
      await openAdd(tester);
      await tester.tap(find.text('Buscar servidor'));
      await tester.pump();
      expect(find.text('Digite o endereço do servidor.'), findsOneWidget);
      await tester.enterText(addressField(), 'isso não é um endereço');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pump();
      expect(find.textContaining('Isso não parece um endereço'), findsOneWidget);
      expect(pairer.calls, 0);
    });

    testWidgets('o código só liga depois de achar o servidor, e "Parear" exige os 6 dígitos', (tester) async {
      await pump(tester);
      await openAdd(tester);
      expect(codeEnabled(tester), isFalse);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();
      expect(codeEnabled(tester), isTrue);
      expect(find.text('Parear'), findsOneWidget);
      FilledButton pairButton() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Parear'));
      expect(pairButton().onPressed, isNull, reason: 'required: empty does not go');
      await tester.enterText(codeField(), '12ab34');
      await tester.pump();
      expect(tester.widget<TextField>(codeField()).controller!.text, '1234', reason: 'only digits are accepted');
      expect(pairButton().onPressed, isNull);
      await tester.enterText(codeField(), '1234567890');
      await tester.pump();
      expect(tester.widget<TextField>(codeField()).controller!.text, '123456', reason: 'at most six');
      expect(pairButton().onPressed, isNotNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('código errado: avisa quantas tentativas restam e, na terceira, desiste', (tester) async {
      final c = await pump(tester);
      await openAdd(tester);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();

      await tester.enterText(codeField(), '000000');
      await tester.pump();
      await tester.tap(find.text('Parear'));
      await tester.pump();
      expect(find.textContaining('Restam 2 tentativas'), findsOneWidget);
      expect(tester.widget<TextField>(codeField()).controller!.text, isEmpty, reason: 'a wrong code is cleared');
      await tester.enterText(codeField(), '111111');
      await tester.pump();
      await tester.tap(find.text('Parear'));
      await tester.pump();
      expect(find.textContaining('Resta 1 tentativa'), findsOneWidget);
      await tester.enterText(codeField(), '222222');
      await tester.pump();
      await tester.tap(find.text('Parear'));
      await tester.pumpAndSettle();
      expect(find.textContaining('desconfie'), findsOneWidget);
      expect(c.read(serverListControllerProvider).current.selected, isNull);
    });

    testWidgets('código certo: o servidor é adicionado, escolhido e confiável', (tester) async {
      final c = await pump(tester);
      await openAdd(tester);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();
      await tester.enterText(codeField(), '123 456'.replaceAll(' ', ''));
      await tester.pump();
      await tester.tap(find.text('Parear'));
      await tester.pumpAndSettle();
      expect(find.text(AddServerDialog.title), findsNothing, reason: 'closed on success');
      final selected = c.read(serverListControllerProvider).current.selected!;
      expect(selected.trusted, isTrue);
      expect(selected.baseUri?.scheme, 'https');
    });

    testWidgets('sem HTTPS no endereço digitado: explica e não pede código', (tester) async {
      await pump(tester, tls: false);
      await openAdd(tester);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('não oferece conexão segura'), findsOneWidget);
      expect(codeEnabled(tester), isFalse);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('servidor mudo ou ocupado: mostra o motivo e deixa tentar de novo', (tester) async {
      await pump(tester, pairer: FakePairer(['123456'], result: const PairingFailed(PairingFailure.busy)));
      await openAdd(tester);
      await tester.enterText(addressField(), 'casa.lan:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Outro aparelho está pareando'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('com o teclado aberto e pouca altura, a tela rola e não estoura', (tester) async {
      // the dialog alone, on a short screen (the login page behind it is not what is tested here)
      tester.view.physicalSize = const Size(900, 1280); // 450 x 640 dp, keyboard 280 dp
      tester.view.devicePixelRatio = 2;
      tester.view.viewInsets = const FakeViewPadding(bottom: 560);
      addTearDown(tester.view.reset);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverTrustProvider.overrideWithValue(ServerTrust(MemoryKeyValueStore())),
            pairedStoreProvider.overrideWithValue(MemoryPairedStore()),
            digitsPairerProvider.overrideWithValue(FakePairer(['123456']).call),
            tlsOfferProvider.overrideWithValue((_) async => const TlsOffer(port: 8443)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(onPressed: () => AddServerDialog.show(context), child: const Text('abrir')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.widgetWithText(TextField, AddServerDialog.addressLabel), '192.168.1.5:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Parear'), findsOneWidget, reason: 'still reachable by scrolling');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('toques repetidos em "Buscar servidor" abrem uma sessão só', (tester) async {
      final pairer = FakePairer(['123456']);
      await pump(tester, pairer: pairer);
      await openAdd(tester);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.tap(find.text('Buscar servidor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(pairer.calls, 1);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });
}
