import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/presentation/widgets/auth_form.dart';

Future<void> pumpForm(
  WidgetTester tester, {
  VoidCallback? onOffline,
  bool showSubtitle = false,
  Size size = const Size(450, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AuthForm(
            onContinueOffline: onOffline,
            showSubtitle: showSubtitle,
          ),
        ),
      ),
    ),
  );
}

bool obscured(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('password-field')))
    .obscureText;

void main() {
  testWidgets('toques repetidos em MOSTRAR/OCULTAR terminam no estado certo', (
    tester,
  ) async {
    await pumpForm(tester);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text(obscured(tester) ? 'MOSTRAR' : 'OCULTAR'));
      await tester.pump();
    }
    expect(obscured(tester), isFalse);
  });

  testWidgets('alternar login/cadastro não apaga o que foi digitado', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.enterText(
      find.byKey(const Key('email-field')),
      'ana@casa.local',
    );
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'segredo123',
    );

    await tester.tap(find.text('Criar conta').last);
    await tester.pump();
    await tester.tap(find.text('Entrar').last);
    await tester.pump();
    await tester.tap(find.text('Criar conta').last);
    await tester.pump();

    expect(find.byKey(const Key('username-field')), findsOneWidget);
    expect(find.text('ana@casa.local'), findsOneWidget);
    final typed = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('password-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(typed.controller.text, 'segredo123');
    expect(typed.obscureText, isTrue);
  });

  testWidgets('aceita texto vazio, enorme, com espaços e emoji', (
    tester,
  ) async {
    await pumpForm(tester);
    for (final value in ['', '   ', 'a' * 50000, 'çãõ 🚀 <script>']) {
      await tester.enterText(find.byKey(const Key('email-field')), value);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('"Manter conectado" começa marcado e alterna', (tester) async {
    await pumpForm(tester);
    bool checked() => tester.widget<Checkbox>(find.byType(Checkbox)).value!;
    expect(checked(), isTrue);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(checked(), isFalse);
    await tester.tap(find.text('Manter conectado')); // the text toggles it too
    await tester.pump();
    expect(checked(), isTrue);
  });

  testWidgets('botão offline chama o callback uma vez por toque', (
    tester,
  ) async {
    var calls = 0;
    await pumpForm(tester, onOffline: () => calls++);
    final button = find.text('Continuar offline neste dispositivo');
    await tester.tap(button);
    await tester.tap(button);
    expect(calls, 2);
  });

  testWidgets('sem callback, o botão offline avisa com um SnackBar', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.tap(find.text('Continuar offline neste dispositivo'));
    await tester.pump();
    expect(find.text('Notas locais chegam em breve.'), findsOneWidget);
  });

  testWidgets('o botão primário segue o modo e não faz nada ainda', (
    tester,
  ) async {
    await pumpForm(tester);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();
    await tester.tap(find.text('Criar conta').last);
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Criar conta'), findsOneWidget);
  });

  testWidgets('o subtítulo só aparece quando pedido e acompanha o modo', (
    tester,
  ) async {
    await pumpForm(tester);
    expect(find.textContaining('Entre para continuar'), findsNothing);

    await pumpForm(tester, showSubtitle: true);
    expect(find.textContaining('Entre para continuar'), findsOneWidget);
    await tester.tap(find.text('Criar conta').last);
    await tester.pump();
    expect(find.textContaining('Crie sua conta'), findsOneWidget);
  });

  testWidgets('tela minúscula e fonte enorme não estouram o layout', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpForm(tester, size: const Size(240, 600), showSubtitle: true);
    await tester.tap(find.text('Criar conta').last);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Chave de recuperação" abre a folha e ela fecha pelo botão', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.tap(find.text('Chave de recuperação'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperar acesso'), findsOneWidget);

    await tester.tap(find.text('Recuperar acesso'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperar acesso'), findsNothing);
  });
}
