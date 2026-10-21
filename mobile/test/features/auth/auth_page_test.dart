import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/features/auth/presentation/pages/auth_page.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  Widget? home,
  double width = 450,
}) async {
  tester.view.physicalSize = Size(width * 2, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: home == null ? const PlanyApp() : MaterialApp(home: home),
    ),
  );
}

bool obscured(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('password-field')))
    .obscureText;

BoxDecoration itemDecoration(WidgetTester tester, String id) =>
    tester.widget<Container>(find.byKey(ValueKey('server-item-$id'))).decoration
        as BoxDecoration;

void main() {
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

    // O botão do cabeçalho passa a mostrar o novo servidor.
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
    // Botão primário também passa a "Criar conta"; o link vira "Entrar".
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
      expect(find.text('→ Rodando em: plany.casa.local'), findsOneWidget);
      expect(find.text('SELF-HOSTED'), findsNWidgets(2));
    });

    testWidgets('desktop: troca de servidor atualiza o rodapé', (tester) async {
      await pumpApp(tester, width: 1300);

      await tester.tap(find.byTooltip('Selecionar servidor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escritório'));
      await tester.pumpAndSettle();

      expect(find.text('ESCRITÓRIO'), findsOneWidget);
      expect(find.text('→ Rodando em: 192.168.0.20'), findsOneWidget);
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
}
