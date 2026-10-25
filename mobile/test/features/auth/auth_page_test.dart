import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/server_discovery.dart';
import 'package:mobile/core/network/server_probe.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/auth/presentation/widgets/pulsing_dot.dart';
import 'package:mobile/features/auth/presentation/widgets/server_dropdown_selector.dart';
import 'package:mobile/features/auth/presentation/pages/auth_page.dart';
import 'package:mobile/features/auth/data/server_trust.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';

import '../../support/discovery_fakes.dart';

/// Opens the app with a fake discovery (by default, the [sampleServers]) and a
/// fixed draw, which picks the first server in the list.
///
/// By default it turns on "reduce motion", which keeps the dot still: with it
/// pulsing forever, `pumpAndSettle` would never settle. The animation tests
/// pass `reduceMotion: false`.
Future<FakeDiscovery> pumpApp(
  WidgetTester tester, {
  Widget? home,
  double width = 450,
  FakeDiscovery? discovery,
  bool reduceMotion = true,
  ServerProbe? probe,
  ServerDiscovery? silent,
  ServerTrust? trust,
}) async {
  final fake = discovery ?? FakeDiscovery(sampleServers);
  tester.view.physicalSize = Size(width * 2, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serverTrustProvider.overrideWithValue(
          trust ?? ServerTrust(MemoryKeyValueStore()),
        ),
        serverDiscoveryProvider.overrideWithValue(silent ?? fake),
        randomProvider.overrideWithValue(FixedRandom(0)),
        serverProbeProvider.overrideWithValue(probe ?? (_) async => true),
      ],
      child: home == null ? const PlanyApp() : MaterialApp(home: home),
    ),
  );
  await tester.pump(); // delivers the discovery's first list
  return fake;
}

bool obscured(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('password-field')))
    .obscureText;

BoxDecoration itemDecoration(WidgetTester tester, String id) =>
    tester.widget<Container>(find.byKey(ValueKey('server-item-$id'))).decoration
        as BoxDecoration;

/// A search that has not answered anything yet.
class _SilentDiscovery implements ServerDiscovery {
  final controller = StreamController<List<DiscoveredServer>>();

  @override
  Stream<List<DiscoveredServer>> watch() => controller.stream;
}

void main() {
  group('animações e esqueleto', () {
    testWidgets('esqueleto no menu até a primeira resposta da busca', (
      tester,
    ) async {
      final silent = _SilentDiscovery();
      addTearDown(silent.controller.close);
      await pumpApp(tester, silent: silent);
      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('servers-skeleton')), findsOneWidget);
      expect(find.text(ServerDropdownSelector.searchingLabel), findsNothing);

      silent.controller.add(const []);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('servers-skeleton')), findsNothing);
      expect(find.text(ServerDropdownSelector.searchingLabel), findsOneWidget);
    });

    testWidgets('um erro na busca também tira o esqueleto', (tester) async {
      final silent = _SilentDiscovery();
      addTearDown(silent.controller.close);
      await pumpApp(tester, silent: silent);
      silent.controller.addError(StateError('sem rede'));
      await tester.pump();
      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('servers-skeleton')), findsNothing);
      expect(
        find.text(ServerDropdownSelector.searchFailedLabel),
        findsOneWidget,
      );
    });

    testWidgets('a seta do botão gira com o menu aberto e volta ao fechar', (
      tester,
    ) async {
      await pumpApp(tester);
      double turns() => tester
          .widget<AnimatedRotation>(
            find.byKey(const ValueKey('server-chevron')),
          )
          .turns;
      expect(turns(), 0);

      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      expect(turns(), 0.5);

      await tester.tapAt(const Offset(5, 700)); // outside the menu
      await tester.pumpAndSettle();
      expect(turns(), 0);
    });

    testWidgets(
      'trocar login/cadastro faz fade: por um instante os dois textos existem',
      (tester) async {
        await pumpApp(tester, reduceMotion: false);
        await tester.tap(find.text('Criar conta'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Bem-vindo de volta'), findsOneWidget);
        expect(find.text('Criar nova conta'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Bem-vindo de volta'), findsNothing);
        expect(find.byKey(const Key('username-field')), findsOneWidget);
      },
    );

    testWidgets('trocar muitas vezes seguidas termina no modo certo', (
      tester,
    ) async {
      await pumpApp(tester, reduceMotion: false);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('toggle-mode')));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Criar nova conta'), findsOneWidget);
      expect(find.text('Bem-vindo de volta'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('app abre na AuthPage com o modo de login', (tester) async {
    await pumpApp(tester);

    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.text('SELF-HOSTED'), findsOneWidget);
    expect(find.text('voce@casa.local'), findsOneWidget);
    expect(find.text('Chave de recuperação'), findsOneWidget);
    expect(find.text('Esqueceu a senha?'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('OU'), findsOneWidget);
  });

  testWidgets('dropdown destaca o servidor selecionado e troca a seleção', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Selecionar servidor'));
    await tester.pumpAndSettle();

    var casa = itemDecoration(tester, 'casa');
    expect(casa.color, AppColors.accentSoft);
    expect((casa.border as Border).top.color, AppColors.accentBorder);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('server-item-casa')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('+ Adicionar servidor...'), findsOneWidget);

    await tester.tap(find.text('Escritório'));
    await tester.pumpAndSettle();

    expect(find.text('ESCRITÓRIO'), findsOneWidget);

    await tester.tap(find.byTooltip('Selecionar servidor'));
    await tester.pumpAndSettle();

    casa = itemDecoration(tester, 'casa');
    final escritorio = itemDecoration(tester, 'escritorio');
    expect(casa.color, isNull);
    expect(escritorio.color, AppColors.accentSoft);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('server-item-escritorio')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('"+ Adicionar servidor..." fecha o menu e avisa o usuário', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Selecionar servidor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Adicionar servidor...'));
    await tester.pumpAndSettle();

    expect(find.text('+ Adicionar servidor...'), findsNothing);
    expect(find.text('Adicionar servidor chega em breve.'), findsOneWidget);
  });

  testWidgets('MOSTRAR / OCULTAR alterna a visibilidade da senha', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(obscured(tester), isTrue);
    expect(find.text('MOSTRAR'), findsOneWidget);

    await tester.tap(find.text('MOSTRAR'));
    await tester.pump();
    expect(obscured(tester), isFalse);
    expect(find.text('OCULTAR'), findsOneWidget);

    await tester.tap(find.text('OCULTAR'));
    await tester.pump();
    expect(obscured(tester), isTrue);
  });

  testWidgets('checkbox "Manter conectado" começa marcado e alterna', (
    tester,
  ) async {
    await pumpApp(tester);

    bool checked() => tester.widget<Checkbox>(find.byType(Checkbox)).value!;
    expect(checked(), isTrue);

    await tester.tap(find.text('Manter conectado'));
    await tester.pump();
    expect(checked(), isFalse);
  });

  testWidgets('alterna para registro com campo Username e volta ao login', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('username-field')), findsNothing);

    await tester.tap(find.text('Criar conta'));
    await tester.pump();

    expect(find.text('Criar nova conta'), findsOneWidget);
    expect(find.text('Bem-vindo de volta'), findsNothing);
    expect(find.byKey(const Key('username-field')), findsOneWidget);
    expect(find.text('Já tem conta? '), findsOneWidget);
    // The primary button also becomes "Criar conta"; the link becomes "Entrar".
    expect(find.text('Criar conta'), findsOneWidget);

    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.byKey(const Key('username-field')), findsNothing);
  });

  testWidgets('botão offline chama o callback', (tester) async {
    var called = 0;
    await pumpApp(tester, home: AuthPage(onContinueOffline: () => called++));

    await tester.tap(find.text('Continuar offline neste dispositivo'));
    await tester.pump();

    expect(called, 1);
  });

  testWidgets('botão offline sem callback mostra aviso', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Continuar offline neste dispositivo'));
    await tester.pump();

    expect(find.text('Notas locais chegam em breve.'), findsOneWidget);
  });

  testWidgets('"Chave de recuperação" abre o modal de recuperação', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Chave de recuperação'));
    await tester.pumpAndSettle();

    expect(find.text('Recuperar acesso'), findsOneWidget);
    expect(find.text('XXXX-XXXX-XXXX'), findsOneWidget);

    await tester.tap(find.text('Recuperar acesso'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperar acesso'), findsNothing);
  });

  group('layout adaptativo', () {
    testWidgets('mobile usa cabeçalho e não mostra o painel desktop', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(
        find.text('Suas notas. Seu servidor.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Roda no seu hardware'), findsNothing);
      expect(find.textContaining('Entre para continuar'), findsNothing);
      expect(find.textContaining('Rodando em'), findsNothing);
    });

    testWidgets('desktop mostra painel institucional e formulário', (
      tester,
    ) async {
      await pumpApp(tester, width: 1300);

      expect(find.text('Roda no seu hardware'), findsOneWidget);
      expect(find.text('Blocos aninhados'), findsOneWidget);
      expect(find.text('Cofre com criptografia'), findsOneWidget);
      expect(find.text('Bem-vindo de volta'), findsOneWidget);
      expect(
        find.text('Entre para continuar de onde você parou.'),
        findsOneWidget,
      );
      expect(find.text('→ Rodando em: plany.casa.local:8080'), findsOneWidget);
      expect(find.text('SELF-HOSTED'), findsNWidgets(2));
    });

    testWidgets('desktop: troca de servidor atualiza o rodapé', (tester) async {
      await pumpApp(tester, width: 1300);

      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escritório'));
      await tester.pumpAndSettle();

      expect(find.text('ESCRITÓRIO'), findsOneWidget);
      expect(find.text('→ Rodando em: 192.168.0.20:8080'), findsOneWidget);
    });

    testWidgets('desktop: senha, registro e offline continuam funcionando', (
      tester,
    ) async {
      var called = 0;
      await pumpApp(
        tester,
        width: 1300,
        home: AuthPage(onContinueOffline: () => called++),
      );

      await tester.tap(find.text('MOSTRAR'));
      await tester.pump();
      expect(obscured(tester), isFalse);

      await tester.tap(find.text('Criar conta'));
      await tester.pump();
      expect(find.text('Criar nova conta'), findsOneWidget);
      expect(
        find.text('Crie sua conta para começar a escrever.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('username-field')), findsOneWidget);

      await tester.tap(find.text('Continuar offline neste dispositivo'));
      await tester.pump();
      expect(called, 1);
    });

    testWidgets('redimensionar alterna entre os layouts', (tester) async {
      await pumpApp(tester);
      expect(find.text('Roda no seu hardware'), findsNothing);

      tester.view.physicalSize = const Size(2600, 1800);
      await tester.pump();
      expect(find.text('Roda no seu hardware'), findsOneWidget);
    });
  });

  group('descoberta de servidores', () {
    testWidgets('sem nenhum servidor: mostra que está procurando', (
      tester,
    ) async {
      await pumpApp(tester, discovery: FakeDiscovery());

      expect(find.text('BUSCANDO'), findsOneWidget);

      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      expect(find.text('Procurando servidores na rede...'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      // adding a server by hand is still possible
      expect(find.text('+ Adicionar servidor...'), findsOneWidget);
    });

    testWidgets('sem servidor, o rodapé do desktop diz que procura', (
      tester,
    ) async {
      await pumpApp(tester, width: 1300, discovery: FakeDiscovery());

      expect(find.text('→ Procurando servidores na rede...'), findsOneWidget);
      expect(find.textContaining('Rodando em'), findsNothing);
    });

    testWidgets('um servidor que aparece depois entra na lista e é escolhido', (
      tester,
    ) async {
      final discovery = await pumpApp(
        tester,
        width: 1300,
        discovery: FakeDiscovery(),
      );
      expect(find.text('BUSCANDO'), findsOneWidget);

      discovery.emit([
        server('Raspberry', addresses: ['192.168.1.116'], port: 8095),
      ]);
      await tester.pumpAndSettle(); // stream -> providers -> widgets

      expect(find.text('RASPBERRY'), findsOneWidget);
      expect(find.text('→ Rodando em: 192.168.1.116:8095'), findsOneWidget);

      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      expect(find.text('Procurando servidores na rede...'), findsNothing);
      expect(
        find.byKey(const ValueKey('server-item-raspberry')),
        findsOneWidget,
      );
    });

    testWidgets('a escolha do usuário resiste a novos anúncios', (
      tester,
    ) async {
      final discovery = await pumpApp(tester);
      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escritório'));
      await tester.pumpAndSettle();
      expect(find.text('ESCRITÓRIO'), findsOneWidget);

      discovery.emit([
        server('Aaa', addresses: ['10.0.0.1']),
        ...sampleServers,
      ]);
      await tester.pumpAndSettle(); // stream -> providers -> widgets

      expect(find.text('ESCRITÓRIO'), findsOneWidget);
    });
  });

  group('servidor com outra identidade', () {
    Future<FakeDiscovery> pumpWithChangedOffice(
      WidgetTester tester, {
      ServerProbe? probe,
    }) async {
      final trust = ServerTrust(MemoryKeyValueStore());
      await trust.load();
      await trust.remember('Escritório', 'aaa');
      final discovery = await pumpApp(
        tester,
        trust: trust,
        probe: probe,
        discovery: FakeDiscovery([
          server('Casa', addresses: ['10.0.0.1']),
          server('Escritório', addresses: ['10.0.0.2'], id: 'bbb'),
        ]),
      );
      await tester.pumpAndSettle();
      return discovery;
    }

    Future<void> chooseOffice(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escritório'));
      await tester.pumpAndSettle();
    }

    testWidgets('pergunta antes, avisa do risco e não troca a escolha', (
      tester,
    ) async {
      await pumpWithChangedOffice(tester);
      await chooseOffice(tester);
      expect(find.text('Este servidor mudou'), findsOneWidget);
      expect(find.textContaining('“Escritório”'), findsOneWidget);
      expect(find.textContaining('senha'), findsOneWidget);
      expect(
        find.text('CASA'),
        findsOneWidget,
        reason: 'ainda no servidor de antes',
      );
    });

    testWidgets('Cancelar fecha a pergunta e fica onde estava', (tester) async {
      await pumpWithChangedOffice(tester);
      await chooseOffice(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Este servidor mudou'), findsNothing);
      expect(find.text('CASA'), findsOneWidget);
      expect(find.text('ESCRITÓRIO'), findsNothing);
    });

    testWidgets('Continuar mesmo assim segue para o servidor', (tester) async {
      await pumpWithChangedOffice(tester);
      await chooseOffice(tester);
      await tester.tap(find.text('Continuar mesmo assim'));
      await tester.pumpAndSettle();
      expect(find.text('Este servidor mudou'), findsNothing);
      expect(find.text('ESCRITÓRIO'), findsOneWidget);
    });

    testWidgets(
      'continuar com um servidor que não responde avisa e mantém a escolha',
      (tester) async {
        await pumpWithChangedOffice(tester, probe: (_) async => false);
        await chooseOffice(tester);
        await tester.tap(find.text('Continuar mesmo assim'));
        await tester.pumpAndSettle();
        expect(find.text('Escritório não respondeu.'), findsOneWidget);
        expect(find.text('CASA'), findsOneWidget);
      },
    );

    testWidgets('perguntar de novo depois de cancelar funciona', (
      tester,
    ) async {
      await pumpWithChangedOffice(tester);
      await chooseOffice(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await chooseOffice(tester);
      expect(find.text('Este servidor mudou'), findsOneWidget);
    });
  });

  group('lista ao vivo e servidor desconectado', () {
    PulsingDot dot(WidgetTester tester, String key) =>
        tester.widget<PulsingDot>(find.byKey(ValueKey(key)));

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
    }

    final withoutCasa = sampleServers.sublist(1);

    testWidgets(
      'a bolinha é verde com o servidor na rede e fica à esquerda do nome',
      (tester) async {
        await pumpApp(tester);

        final d = dot(tester, 'server-status-dot');
        expect(d.color, AppColors.accentBorder);
        expect(d.pulsing, isTrue);
        expect(
          tester.getCenter(find.byKey(const ValueKey('server-status-dot'))).dx,
          lessThan(tester.getCenter(find.text('CASA')).dx),
        );
      },
    );

    testWidgets('a bolinha tem o tamanho de uma letra e uma folga até o nome', (
      tester,
    ) async {
      await pumpApp(tester);

      final dotBox = find.byKey(const ValueKey('server-status-dot'));
      // 11 pt text: the dot is ~80% of that, close to the height of a letter
      expect(tester.getSize(dotBox), const Size(9, 9));
      expect(dotDiameterFor(11), 9);
      final gap =
          tester.getTopLeft(find.text('CASA')).dx -
          tester.getTopRight(dotBox).dx;
      expect(gap, 10);
    });

    testWidgets(
      'o servidor escolhido sai da rede: continua lá, com bolinha vermelha',
      (tester) async {
        final discovery = await pumpApp(tester);
        discovery.emit(withoutCasa);
        await tester.pumpAndSettle();

        expect(
          find.text('CASA'),
          findsOneWidget,
          reason: 'não some de repente',
        );
        final d = dot(tester, 'server-status-dot');
        expect(d.color, AppColors.offline);
        expect(d.pulsing, isTrue);
      },
    );

    testWidgets('volta para a rede: a bolinha volta a ser verde', (
      tester,
    ) async {
      final discovery = await pumpApp(tester);
      discovery.emit(withoutCasa);
      await tester.pumpAndSettle();
      discovery.emit(sampleServers);
      await tester.pumpAndSettle();

      expect(dot(tester, 'server-status-dot').color, AppColors.accentBorder);
    });

    testWidgets('sem servidor escolhido a bolinha é cinza e não pulsa', (
      tester,
    ) async {
      await pumpApp(tester, discovery: FakeDiscovery());

      final d = dot(tester, 'server-status-dot');
      expect(d.color, AppColors.textMuted);
      expect(d.pulsing, isFalse);
    });

    testWidgets('com todos na rede não há seção "Desconectados"', (
      tester,
    ) async {
      await pumpApp(tester);
      await openMenu(tester);

      expect(find.text('DESCONECTADOS'), findsNothing);
      expect(find.text('DISPONÍVEIS'), findsNothing);
    });

    testWidgets(
      'o escolhido desconectado aparece em "Desconectados", abaixo dos disponíveis',
      (tester) async {
        final discovery = await pumpApp(tester);
        discovery.emit(withoutCasa);
        await tester.pumpAndSettle();
        await openMenu(tester);

        expect(find.text('DISPONÍVEIS'), findsOneWidget);
        expect(find.text('DESCONECTADOS'), findsOneWidget);
        final casa = find.byKey(const ValueKey('server-item-casa'));
        final escritorio = find.byKey(const ValueKey('server-item-escritorio'));
        final nuvem = find.byKey(const ValueKey('server-item-nuvem'));
        expect(casa, findsOneWidget);
        // top to bottom order: available, label, disconnected
        expect(
          tester.getTopLeft(escritorio).dy,
          lessThan(tester.getTopLeft(nuvem).dy),
        );
        expect(
          tester.getTopLeft(nuvem).dy,
          lessThan(tester.getTopLeft(find.text('DESCONECTADOS')).dy),
        );
        expect(
          tester.getTopLeft(find.text('DESCONECTADOS')).dy,
          lessThan(tester.getTopLeft(casa).dy),
        );
        // the disconnected one is still marked as chosen, in red
        expect(
          find.descendant(of: casa, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        expect(
          ((tester.widget<Container>(casa)).decoration as BoxDecoration)
              .border!
              .top
              .color,
          AppColors.offline,
        );
      },
    );

    testWidgets(
      'com o menu aberto, um servidor novo aparece sem fechar nem reabrir',
      (tester) async {
        final discovery = await pumpApp(tester);
        await openMenu(tester);
        expect(
          find.byKey(const ValueKey('server-item-raspberry')),
          findsNothing,
        );

        discovery.emit([
          ...sampleServers,
          server('Raspberry', addresses: ['192.168.1.116'], port: 8095),
        ]);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('server-item-raspberry')),
          findsOneWidget,
        );
        expect(find.text('192.168.1.116:8095'), findsOneWidget);
      },
    );

    testWidgets('com o menu aberto, um servidor que sai desaparece da lista', (
      tester,
    ) async {
      final discovery = await pumpApp(tester);
      await openMenu(tester);
      expect(find.byKey(const ValueKey('server-item-nuvem')), findsOneWidget);

      discovery.emit(
        sampleServers.sublist(0, 2),
      ); // Nuvem leaves, which was not the chosen one
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('server-item-nuvem')), findsNothing);
      expect(find.text('DESCONECTADOS'), findsNothing);
    });

    testWidgets(
      'com o menu aberto, o escolhido que sai vai para "Desconectados" e volta',
      (tester) async {
        final discovery = await pumpApp(tester);
        await openMenu(tester);
        expect(find.text('DESCONECTADOS'), findsNothing);

        discovery.emit(withoutCasa);
        await tester.pumpAndSettle();
        expect(find.text('DESCONECTADOS'), findsOneWidget);
        expect(dot(tester, 'server-status-dot').color, AppColors.offline);

        discovery.emit(sampleServers);
        await tester.pumpAndSettle();
        expect(find.text('DESCONECTADOS'), findsNothing);
        expect(dot(tester, 'server-status-dot').color, AppColors.accentBorder);
      },
    );

    testWidgets(
      'com o menu aberto e sem servidores, mostra a busca e depois a lista',
      (tester) async {
        final discovery = await pumpApp(tester, discovery: FakeDiscovery());
        await openMenu(tester);
        expect(
          find.text(ServerDropdownSelector.searchingLabel),
          findsOneWidget,
        );

        discovery.emit(sampleServers);
        await tester.pumpAndSettle();
        expect(find.text(ServerDropdownSelector.searchingLabel), findsNothing);
        expect(find.byKey(const ValueKey('server-item-casa')), findsOneWidget);
      },
    );

    testWidgets('escolher um disponível larga o desconectado', (tester) async {
      final discovery = await pumpApp(tester);
      discovery.emit(withoutCasa);
      await tester.pumpAndSettle();
      await openMenu(tester);

      await tester.tap(find.text('Nuvem'));
      await tester.pumpAndSettle();
      expect(find.text('NUVEM'), findsOneWidget);
      expect(dot(tester, 'server-status-dot').color, AppColors.accentBorder);

      await openMenu(tester);
      expect(find.text('DESCONECTADOS'), findsNothing);
      expect(find.byKey(const ValueKey('server-item-casa')), findsNothing);
    });

    testWidgets('tocar no desconectado fecha o menu e nada muda', (
      tester,
    ) async {
      final discovery = await pumpApp(tester);
      discovery.emit(withoutCasa);
      await tester.pumpAndSettle();
      await openMenu(tester);

      await tester.tap(find.byKey(const ValueKey('server-item-casa')));
      await tester.pumpAndSettle();

      expect(find.text('DESCONECTADOS'), findsNothing, reason: 'menu fechado');
      expect(find.text('CASA'), findsOneWidget);
      expect(dot(tester, 'server-status-dot').color, AppColors.offline);
    });

    testWidgets('servidor que não responde: avisa e a escolha fica', (
      tester,
    ) async {
      await pumpApp(tester, probe: (_) async => false);
      await openMenu(tester);

      await tester.tap(find.byKey(const ValueKey('server-item-escritorio')));
      await tester.pumpAndSettle();

      expect(find.text('Escritório não respondeu.'), findsOneWidget);
      expect(find.text('CASA'), findsOneWidget);
    });

    testWidgets(
      'enquanto testa, o botão diz "Abrindo" e o menu não aceita toques',
      (tester) async {
        final gate = Completer<bool>();
        await pumpApp(tester, probe: (_) => gate.future);
        await openMenu(tester);

        await tester.tap(find.byKey(const ValueKey('server-item-escritorio')));
        await tester.pump();
        expect(find.text('ABRINDO ESCRITÓRIO…'), findsOneWidget);

        // a second tap (menu reopened) triggers no new query nor error
        await openMenu(tester);
        await tester.tap(find.byKey(const ValueKey('server-item-nuvem')));
        await tester.pumpAndSettle();
        expect(find.text('ABRINDO ESCRITÓRIO…'), findsOneWidget);

        gate.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('ESCRITÓRIO'), findsOneWidget);
      },
    );

    testWidgets('a busca que falha é avisada no menu', (tester) async {
      final failing = FakeDiscovery();
      await pumpApp(tester, discovery: failing);
      failing.fail(StateError('sem permissão de rede'));
      await tester.pumpAndSettle();
      await openMenu(tester);

      expect(
        find.text(ServerDropdownSelector.searchFailedLabel),
        findsOneWidget,
      );
    });

    testWidgets('um nome longo é cortado com reticências, sem estourar', (
      tester,
    ) async {
      await pumpApp(
        tester,
        discovery: FakeDiscovery([
          server(
            'Servidor da Sala de Estar da Casa de Praia',
            addresses: ['10.0.0.1'],
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('SERVIDOR DA SALA'), findsOneWidget);
    });
  });

  group('desktop', () {
    PulsingDot footerDot(WidgetTester tester) => tester.widget<PulsingDot>(
      find.byKey(const ValueKey('server-footer-dot')),
    );

    testWidgets(
      'o rodapé mostra bolinha verde e o endereço com o servidor na rede',
      (tester) async {
        await pumpApp(tester, width: 1300);

        expect(
          find.text('→ Rodando em: plany.casa.local:8080'),
          findsOneWidget,
        );
        expect(footerDot(tester).color, AppColors.accentBorder);
        expect(footerDot(tester).pulsing, isTrue);
      },
    );

    testWidgets(
      'o rodapé fica vermelho e diz "Desconectado de" quando o servidor sai',
      (tester) async {
        final discovery = await pumpApp(tester, width: 1300);
        discovery.emit(sampleServers.sublist(1));
        await tester.pumpAndSettle();

        expect(
          find.text('→ Desconectado de: plany.casa.local:8080'),
          findsOneWidget,
        );
        expect(find.textContaining('Rodando em'), findsNothing);
        expect(footerDot(tester).color, AppColors.offline);
        // the header button too
        expect(
          tester
              .widget<PulsingDot>(
                find.byKey(const ValueKey('server-status-dot')),
              )
              .color,
          AppColors.offline,
        );
      },
    );

    testWidgets('sem servidor o rodapé não tem bolinha', (tester) async {
      await pumpApp(tester, width: 1300, discovery: FakeDiscovery());

      expect(find.byKey(const ValueKey('server-footer-dot')), findsNothing);
    });

    testWidgets(
      'a bolinha do rodapé tem o tamanho de uma letra e uma folga até o texto',
      (tester) async {
        await pumpApp(tester, width: 1300);

        final dotBox = find.byKey(const ValueKey('server-footer-dot'));
        expect(
          tester.getSize(dotBox),
          const Size(10, 10),
        ); // ~80% of a 12 pt text
        final gap =
            tester
                .getTopLeft(find.text('→ Rodando em: plany.casa.local:8080'))
                .dx -
            tester.getTopRight(dotBox).dx;
        expect(gap, 10);
      },
    );

    testWidgets(
      'o seletor do desktop é mais largo que o do celular e cabe o nome inteiro',
      (tester) async {
        final longName = server(
          'Servidor da Sala de Estar',
          addresses: ['10.0.0.1'],
        );
        double buttonWidth() => tester
            .getSize(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('server-status-dot')),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .width;

        await pumpApp(tester, width: 450, discovery: FakeDiscovery([longName]));
        final mobile = buttonWidth();
        expect(
          mobile,
          ServerDropdownSelector.defaultMaxWidth,
          reason: 'o nome ocupa tudo e é cortado',
        );
        expect(tester.takeException(), isNull);

        await pumpApp(
          tester,
          width: 1300,
          discovery: FakeDiscovery([longName]),
        );
        expect(buttonWidth(), greaterThan(mobile));
        expect(find.text('SERVIDOR DA SALA DE ESTAR'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a seção "Desconectados" também funciona no desktop', (
      tester,
    ) async {
      final discovery = await pumpApp(tester, width: 1300);
      discovery.emit(sampleServers.sublist(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();

      expect(find.text('DESCONECTADOS'), findsOneWidget);
      expect(find.byKey(const ValueKey('server-item-casa')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
