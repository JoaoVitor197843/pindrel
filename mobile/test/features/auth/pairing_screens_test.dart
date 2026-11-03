import 'dart:io';

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
  FakeMasterPairer? master,
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
        masterPairerProvider.overrideWithValue((master ?? FakeMasterPairer()).call),
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

/// The first step of the pairing screen of a server on the network: the code of the room opened on the server's page.
Future<void> enterRoom(WidgetTester tester, [String room = '4821']) async {
  await tester.enterText(find.byKey(const ValueKey('room-field')), room);
  await tester.pump();
  await tester.tap(find.text('Continuar'));
  await tester.pumpAndSettle();
}

final _pem = File('test/fixtures/pairing/good-ca.pem').readAsStringSync();

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
      expect(find.byKey(const ValueKey('room-field')), findsOneWidget, reason: 'first the room opened on the server\'s page');
      expect(find.byKey(const ValueKey('pairing-digits')), findsNothing, reason: 'no session before the room code');
      await enterRoom(tester);
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
      await enterRoom(tester);
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
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('room-field')), '4821');
      await tester.pump();
      await tester.tap(find.text('Continuar'));
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
      await enterRoom(tester);
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
        await enterRoom(tester);
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
      await enterRoom(tester);
      expect(find.bySemanticsLabel('Número de conferência: 1 2 3 4 5 6'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });

  group('retirar a confiança', () {
    Future<ServerTrust> trustedCasa() async {
      final trust = ServerTrust(MemoryKeyValueStore());
      await trust.remember('Casa', '');
      return trust;
    }

    testWidgets('só os confiáveis têm o botão, e tocar nele não escolhe o servidor', (tester) async {
      final c = await pump(tester, trust: await trustedCasa());
      await openMenu(tester);
      expect(find.byKey(const ValueKey('server-revoke-casa')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-revoke-nuvem')), findsNothing, reason: 'a new server has nothing to remove');
      expect(find.byTooltip('Remover confiança em Casa'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-revoke-casa')));
      await tester.pumpAndSettle();
      expect(find.text('Remover confiança em Casa?'), findsOneWidget);
      expect(c.read(serverListControllerProvider).current.selected, isNull, reason: 'the tap on the button is not a choice');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-badge-casa')), findsNothing);
    });

    testWidgets('Cancelar deixa tudo como estava', (tester) async {
      final c = await pump(tester, trust: await trustedCasa());
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-revoke-casa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(c.read(serverListControllerProvider).current.available.firstWhere((s) => s.name == 'Casa').trusted, isTrue);
    });

    testWidgets('remover: o servidor, ainda na rede, volta a pedir pareamento e deixa de ser o escolhido', (tester) async {
      final c = await pump(tester, trust: await trustedCasa());
      final controller = c.read(serverListControllerProvider);
      await controller.select(controller.current.available.first);
      await tester.pump();
      expect(find.text('CASA'), findsOneWidget);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-revoke-casa')));
      await tester.pumpAndSettle();
      expect(find.text('Ele também deixa de ser o servidor escolhido.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('revoke-remove')));
      await tester.pumpAndSettle();
      expect(controller.current.selected, isNull);
      expect(find.text('3 DISPONÍVEIS'), findsOneWidget);
      await openMenu(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('server-item-casa')), matching: find.text('PAREAR')), findsOneWidget);
      // and it can be paired again with a tap
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();
      expect(find.text('Parear com Casa'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('remover e parear de novo: abre a tela dos números na hora, e concluir o torna confiável outra vez', (tester) async {
      final c = await pump(tester, trust: await trustedCasa());
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-revoke-casa')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('revoke-repair')));
      await tester.pumpAndSettle();
      expect(find.text('Parear com Casa'), findsOneWidget);
      await enterRoom(tester);
      expect(find.text('123 456'), findsOneWidget);
      await tester.tap(find.text('São iguais'));
      await tester.pumpAndSettle();
      final selected = c.read(serverListControllerProvider).current.selected!;
      expect(selected.name, 'Casa');
      expect(selected.trusted, isTrue);
    });

    testWidgets('o servidor que só existe pelo pareamento some da lista ao remover', (tester) async {
      final store = MemoryPairedStore();
      await store.save(PairedServer(hostPort: '192.168.1.50:8443', fingerprint: fingerprintOfPem(_pem), caPem: _pem, name: 'Sítio', serverId: 'sss'));
      await pump(tester, store: store);
      await openMenu(tester);
      expect(find.byKey(const ValueKey('server-item-sitio')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-revoke-sitio')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('revoke-remove')));
      await tester.pumpAndSettle();
      await openMenu(tester);
      expect(find.byKey(const ValueKey('server-item-sitio')), findsNothing);
      expect(await store.all(), isEmpty);
    });
  });

  group('a sala e o código mestre ao parear um servidor da rede', () {
    Future<void> openCasa(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();
    }

    testWidgets('o primeiro passo explica de onde vem o código e só deixa seguir com 4 dígitos', (tester) async {
      await pump(tester);
      await openCasa(tester);
      expect(find.textContaining('Gerar código de pareamento'), findsOneWidget);
      FilledButton go() => tester.widget<FilledButton>(find.byKey(const ValueKey('pairing-go')));
      expect(go().onPressed, isNull, reason: 'empty does not go');
      await tester.enterText(find.byKey(const ValueKey('room-field')), '48');
      await tester.pump();
      expect(go().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('room-field')), '48a2b1c9');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('room-field'))).controller!.text, '4821', reason: 'digits only, at most four');
      expect(go().onPressed, isNotNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('uma sala que não existe é dita em palavras simples e deixa digitar outro código', (tester) async {
      final pairer = FakePairer(['123456'], validRoom: '4821');
      await pump(tester, pairer: pairer);
      await openCasa(tester);
      await enterRoom(tester, '0000');
      expect(find.textContaining('não existe (mais)'), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-digits')), findsNothing);
      await tester.tap(find.text('Digitar outro código'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('room-field'))).controller!.text, isEmpty, reason: 'starts over');
      await enterRoom(tester, '4821');
      expect(find.text('123 456'), findsOneWidget);
      expect(pairer.rooms, ['0000', '4821']);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('com o código mestre: sem números para comparar, e o servidor fica pareado', (tester) async {
      final m = FakeMasterPairer(name: 'Casa');
      final c = await pump(tester, master: m);
      await openCasa(tester);
      await tester.tap(find.byKey(const ValueKey('master-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-field')), findsNothing);
      FilledButton go() => tester.widget<FilledButton>(find.byKey(const ValueKey('pairing-go')));
      expect(go().onPressed, isNull, reason: 'a code that is not well formed does not go');
      await tester.enterText(find.byKey(const ValueKey('master-field')), 'uuuu');
      await tester.pump();
      expect(go().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('master-field')), '0410 6105 0r3g g28a');
      await tester.pump();
      expect(go().onPressed, isNotNull, reason: 'typed any way: lower case, spaces for dashes, o for zero');
      await tester.tap(find.text('Parear com o código mestre'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pairing-digits')), findsNothing, reason: 'nothing to compare');
      final selected = c.read(serverListControllerProvider).current.selected!;
      expect(selected.name, 'Casa');
      expect(selected.trusted, isTrue);
      expect(m.tried, ['0410 6105 0r3g g28a']);
    });

    testWidgets('código mestre errado: explica, nada é guardado, e deixa digitar de novo', (tester) async {
      final c = await pump(tester, master: FakeMasterPairer(accepts: 'ZZZZ-ZZZZ-ZZZZ-ZZZZ'));
      await openCasa(tester);
      await tester.tap(find.byKey(const ValueKey('master-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('master-field')), '0000-0000-0000-0000');
      await tester.pump();
      await tester.tap(find.text('Parear com o código mestre'));
      await tester.pumpAndSettle();
      expect(find.textContaining('código mestre foi recusado'), findsOneWidget);
      expect(c.read(serverListControllerProvider).current.selected, isNull);
      await tester.tap(find.text('Digitar outro código'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('master-field')), findsOneWidget, reason: 'back at the master code, not the room');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('o código mestre nunca aparece em texto fora do campo (nem no semântico do diálogo)', (tester) async {
      await pump(tester);
      await openCasa(tester);
      await tester.tap(find.byKey(const ValueKey('master-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('master-field')), '0410-6105-0R3G-G28A');
      await tester.pump();
      expect(find.text('0410-6105-0R3G-G28A'), findsOneWidget, reason: 'only inside the field the person typed it in');
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
    Finder roomField() => find.byKey(const ValueKey('room-field'));

    /// Address and room typed, "Buscar servidor" tapped (the room is required: without it nothing is searched).
    Future<void> search(WidgetTester tester, String address, {String room = '4821'}) async {
      await tester.enterText(addressField(), address);
      await tester.enterText(roomField(), room);
      await tester.pump();
      await tester.tap(find.text('Buscar servidor'));
    }

    testWidgets('o nome é opcional: vazio usa o do servidor; digitado, é o que aparece, e é guardado', (tester) async {
      final store = MemoryPairedStore();
      final c = await pump(tester, pairer: FakePairer(['123456'], name: 'Raspberry'), store: store);
      await openAdd(tester);
      expect(find.text(AddServerDialog.nameLabel), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('server-name-field')), '  Casa   da\tpraia \n');
      await search(tester, '192.168.1.5:8086');
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
      await search(tester, '192.168.1.5:8086');
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
      await search(tester, 'isso não é um endereço');
      await tester.pump();
      expect(find.textContaining('Isso não parece um endereço'), findsOneWidget);
      expect(pairer.calls, 0);
    });

    testWidgets('o código só liga depois de achar o servidor, e "Parear" exige os 6 dígitos', (tester) async {
      await pump(tester);
      await openAdd(tester);
      expect(codeEnabled(tester), isFalse);
      await search(tester, '192.168.1.5:8086');
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
      await search(tester, '192.168.1.5:8086');
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
      await search(tester, '192.168.1.5:8086');
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
      await search(tester, '192.168.1.5:8086');
      await tester.pumpAndSettle();
      expect(find.textContaining('não oferece conexão segura'), findsOneWidget);
      expect(codeEnabled(tester), isFalse);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('servidor mudo ou ocupado: mostra o motivo e deixa tentar de novo', (tester) async {
      await pump(tester, pairer: FakePairer(['123456'], result: const PairingFailed(PairingFailure.busy)));
      await openAdd(tester);
      await search(tester, 'casa.lan:8086');
      await tester.pumpAndSettle();
      expect(find.textContaining('Outro aparelho está pareando'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('o código da sala é obrigatório: sem ele nada é buscado, e a dica diz onde conseguir', (tester) async {
      final pairer = FakePairer(['123456']);
      await pump(tester, pairer: pairer);
      await openAdd(tester);
      expect(find.text(AddServerDialog.roomLabel), findsOneWidget);
      expect(find.textContaining('obrigatório'), findsWidgets);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.pump();
      await tester.tap(find.text('Buscar servidor'));
      await tester.pump();
      expect(find.textContaining('Digite o código da sala (4 dígitos)'), findsOneWidget);
      expect(pairer.calls, 0);
      await tester.enterText(roomField(), '12');
      await tester.pump();
      await tester.tap(find.text('Buscar servidor'));
      await tester.pump();
      expect(pairer.calls, 0, reason: 'two digits are not a room');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('uma sala que o servidor não conhece: avisa, destrava o formulário e deixa tentar outra', (tester) async {
      final pairer = FakePairer(['123456']);
      await pump(tester, pairer: pairer);
      await openAdd(tester);
      await search(tester, '192.168.1.5:8086', room: '0000');
      await tester.pumpAndSettle();
      expect(find.textContaining('não existe (mais)'), findsOneWidget);
      expect(tester.widget<TextField>(roomField()).enabled, isTrue, reason: 'unlocked: it can be fixed');
      await tester.enterText(roomField(), '4821');
      await tester.pump();
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(codeEnabled(tester), isTrue);
      expect(pairer.rooms, ['0000', '4821']);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('com o código mestre: endereço e código bastam, sem sala e sem os 6 dígitos', (tester) async {
      final m = FakeMasterPairer(name: 'Raspberry');
      final c = await pump(tester, master: m);
      await openAdd(tester);
      await tester.tap(find.byKey(const ValueKey('master-toggle')));
      await tester.pumpAndSettle();
      expect(roomField(), findsNothing);
      expect(codeField(), findsNothing, reason: 'nothing to type from the page');
      expect(find.text(AddServerDialog.masterLabel), findsOneWidget);
      await tester.enterText(addressField(), '192.168.1.5:8086');
      await tester.tap(find.text('Parear com o código mestre'));
      await tester.pump();
      expect(find.textContaining('16 letras e números'), findsOneWidget, reason: 'the code is required too');
      expect(m.tried, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('master-field')), '0410-6105-0R3G-G28A');
      await tester.tap(find.text('Parear com o código mestre'));
      await tester.pumpAndSettle();
      final selected = c.read(serverListControllerProvider).current.selected!;
      expect(selected.name, 'Raspberry');
      expect(selected.trusted, isTrue);
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
            masterPairerProvider.overrideWithValue(FakeMasterPairer().call),
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
      await tester.enterText(find.byKey(const ValueKey('room-field')), '4821');
      await tester.pump();
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
      await search(tester, '192.168.1.5:8086');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(pairer.calls, 1);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });
}
