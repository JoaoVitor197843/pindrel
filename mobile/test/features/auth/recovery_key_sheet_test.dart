import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/presentation/widgets/recovery_key_sheet.dart';

Future<void> openSheet(WidgetTester tester, {double bottomInset = 0}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => RecoveryKeySheet.show(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra título, dica do campo e botão', (tester) async {
    await openSheet(tester);
    expect(find.text('Chave de recuperação'), findsOneWidget);
    expect(find.text('XXXX-XXXX-XXXX'), findsOneWidget);
    expect(find.text('Recuperar acesso'), findsOneWidget);
  });

  testWidgets('o campo aceita texto vazio, enorme e com emoji', (tester) async {
    await openSheet(tester);
    for (final v in ['', '  ', 'x' * 50000, '😀-😀']) {
      await tester.enterText(find.byType(TextField), v);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('com o teclado aberto o conteúdo sobe e não estoura', (
    tester,
  ) async {
    await openSheet(tester, bottomInset: 300);
    expect(tester.takeException(), isNull);
    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(RecoveryKeySheet),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect((padding.padding as EdgeInsets).bottom, 24 + 300);
  });

  testWidgets('tocar fora da folha a fecha', (tester) async {
    await openSheet(tester);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryKeySheet), findsNothing);
  });
}
