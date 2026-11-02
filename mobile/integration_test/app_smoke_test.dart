import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

/// Opens the real app on a real platform (a Windows or macOS window, an Android emulator) with its real plugins
/// (secure storage, mDNS) and checks that the login screen shows up and answers taps. It proves "the app opens and
/// does not crash"; the behaviour is covered by the widget tests in test/.
///
/// Run with: fvm flutter test integration_test/app_smoke_test.dart -d DEVICE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The login screen has animations that never stop (the pulsing dot, the logo), so pumpAndSettle would wait forever.
  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('abre o app, mostra o login e responde aos toques', (
    tester,
  ) async {
    app.main();
    await frames(tester);

    expect(find.text('Pindrel'), findsWidgets);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.text('Continuar offline neste dispositivo'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'a primeira tela não pode lançar',
    );

    // typing into a field (not the placeholder text, which would match twice)
    await tester.enterText(find.byType(TextField).first, 'smoke@teste.dev');
    await frames(tester, 2);
    expect(find.text('smoke@teste.dev'), findsOneWidget);

    // login <-> register
    await tester.ensureVisible(find.text('Criar conta'));
    await tester.tap(find.text('Criar conta'));
    await frames(tester, 4);
    expect(find.text('Criar nova conta'), findsOneWidget);
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await frames(tester, 4);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);

    // the offline path answers
    await tester.ensureVisible(
      find.text('Continuar offline neste dispositivo'),
    );
    await tester.tap(find.text('Continuar offline neste dispositivo'));
    await frames(tester, 3);
    expect(find.text('Notas locais chegam em breve.'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
