import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/widgets/pulsing_dot.dart';

Future<void> pumpDot(
  WidgetTester tester, {
  bool pulsing = true,
  bool reduceMotion = false,
  double diameter = 10,
  Color color = Colors.green,
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: PulsingDot(color: color, diameter: diameter, pulsing: pulsing),
      ),
    ),
  );
}

RenderObject paintObject(WidgetTester tester) => tester.renderObject(
  find
      .descendant(
        of: find.byType(PulsingDot),
        matching: find.byType(CustomPaint),
      )
      .first,
);

void main() {
  testWidgets('tem exatamente o diâmetro pedido', (tester) async {
    await pumpDot(tester, diameter: 9);
    expect(tester.getSize(find.byType(PulsingDot)), const Size(9, 9));
  });

  testWidgets('pulsando: a animação roda e desenha o núcleo e o anel', (
    tester,
  ) async {
    await pumpDot(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.hasRunningAnimations, isTrue);
    expect(paintObject(tester), paintsExactlyCountTimes(#drawCircle, 2));
  });

  testWidgets('o anel nasce, cresce e some, e recomeça sem parar', (
    tester,
  ) async {
    await pumpDot(tester);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isTrue, reason: 'passo $i');
      expect(paintObject(tester), paintsExactlyCountTimes(#drawCircle, 2));
    }
  });

  testWidgets('com "reduzir movimento" fica parada e só desenha o núcleo', (
    tester,
  ) async {
    await pumpDot(tester, reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.hasRunningAnimations, isFalse);
    expect(paintObject(tester), paintsExactlyCountTimes(#drawCircle, 1));
  });

  testWidgets('pulsing falso: parada, só o núcleo', (tester) async {
    await pumpDot(tester, pulsing: false);
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.hasRunningAnimations, isFalse);
    expect(paintObject(tester), paintsExactlyCountTimes(#drawCircle, 1));
  });

  testWidgets('para de pulsar quando o servidor deixa de ter estado', (
    tester,
  ) async {
    await pumpDot(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: PulsingDot(color: Colors.grey, diameter: 10, pulsing: false),
        ),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('volta a pulsar quando passa a ter estado', (tester) async {
    await pumpDot(tester, pulsing: false);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: PulsingDot(color: Colors.red, diameter: 10)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('trocar a cor não reinicia nem quebra a animação', (
    tester,
  ) async {
    await pumpDot(tester, color: Colors.green);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: PulsingDot(color: Colors.red, diameter: 10)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.hasRunningAnimations, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sair da tela enquanto pulsa libera o ticker (sem erro)', (
    tester,
  ) async {
    await pumpDot(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
