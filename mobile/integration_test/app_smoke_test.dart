import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

/// Opens the real app on a real platform (a Windows or macOS window, an Android emulator) with its real plugins
/// (secure storage, mDNS) and checks that the login screen shows up and answers taps. It proves "the app opens and
/// does not crash"; the behaviour is covered by the widget tests in test/.
///
/// Run with: fvm flutter test integration_test/app_smoke_test.dart -d DEVICE
/// It opens the app's real data folder and expects no notes in it (as on the CI machines). On a machine with notes of its own
/// point the data elsewhere first: `XDG_DATA_HOME=/tmp/smoke_data ... -d linux`.
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
    // Keeps the full report of every framework error (an overflow names the widget, its constraints and the render tree),
    // because `takeException` alone only says "overflowed by N pixels" and the emulator log is all there is to go on.
    final reports = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      reports.add(details.toString());
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    String screen() {
      final v = tester.view;
      final size = v.physicalSize / v.devicePixelRatio;
      return 'tela: ${size.width.toStringAsFixed(1)} x ${size.height.toStringAsFixed(1)} dp, '
          'escala do texto ${tester.platformDispatcher.textScaleFactor}';
    }

    app.main();
    // the first screen waits for the secure storage (it asks whether a session was kept; up to 4 s when the keyring is
    // slow), so wait for the login to show instead of counting frames
    for (var i = 0; i < 60 && find.text('Bem-vindo de volta').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await frames(tester);

    // the app opens on the login (the notes of the device are one tap away)
    expect(find.text('Pindrel'), findsWidgets);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.text('Continuar offline neste dispositivo'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason:
          'a primeira tela não pode lançar\n${screen()}\n${reports.join('\n---\n')}',
    );

    // typing into a field (not the placeholder text, which would match twice)
    await tester.enterText(find.byType(TextField).first, 'smoke@teste.dev');
    await frames(tester, 2);
    expect(find.text('smoke@teste.dev'), findsOneWidget);

    // the button warns about empty fields instead of calling a server (none was chosen here)
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await frames(tester, 2);
    expect(find.text('Digite a senha.'), findsOneWidget);

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
    // ...and opens the notes of the device: the SQLite file is opened now, so wait for the page instead of counting frames
    for (var i = 0; i < 60 && find.text('Nenhuma página ainda').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Nenhuma página ainda'), findsOneWidget);

    expect(
      tester.takeException(),
      isNull,
      reason: '${screen()}\n${reports.join('\n---\n')}',
    );
  });
}
