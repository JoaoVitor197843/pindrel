import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/logo/season.dart';
import 'package:mobile/features/auth/presentation/logo/stage.dart';
import 'package:mobile/features/auth/presentation/widgets/logo_mark.dart';

Widget app({LogoTheme theme = LogoTheme.normal}) => MaterialApp(
  home: Scaffold(
    body: Center(child: LogoMark(theme: theme)),
  ),
);

Finder get stage => find.byType(LogoStage);

Future<void> tapLogo(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(find.text('P'));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('cinco toques rápidos mostram a cena e depois tudo some', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tapLogo(tester, 4);
    expect(stage, findsNothing);
    await tapLogo(tester, 1);
    expect(stage, findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(stage, findsNothing);
    expect(find.text('P'), findsOneWidget);
  });

  testWidgets('quatro toques e uma pausa não disparam', (tester) async {
    await tester.pumpWidget(app());
    await tapLogo(tester, 4);
    await tester.pump(const Duration(milliseconds: 1900));
    await tapLogo(tester, 1);
    expect(stage, findsNothing);
  });

  testWidgets('toques durante a cena são ignorados', (tester) async {
    await tester.pumpWidget(app(theme: LogoTheme.d1));
    await tapLogo(tester, 5);
    await tapLogo(tester, 30);
    expect(stage, findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(stage, findsNothing);
  });

  testWidgets('todos os temas rodam do começo ao fim e limpam o palco', (
    tester,
  ) async {
    for (final theme in LogoTheme.values) {
      await tester.pumpWidget(app(theme: theme));
      await tapLogo(tester, 5);
      expect(stage, findsOneWidget, reason: theme.name);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(stage, findsNothing, reason: theme.name);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('sair da tela no meio da cena remove o palco', (tester) async {
    await tester.pumpWidget(app());
    await tapLogo(tester, 5);
    expect(stage, findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(stage, findsNothing);
  });

  testWidgets('ir para segundo plano cancela a cena', (tester) async {
    await tester.pumpWidget(app());
    await tapLogo(tester, 5);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(stage, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('com redução de movimento só pisca, sem palco', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app());
    await tapLogo(tester, 5);
    expect(stage, findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });
}
