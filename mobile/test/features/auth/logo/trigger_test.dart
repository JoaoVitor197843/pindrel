import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/logo/trigger.dart';

void main() {
  testWidgets('cinco toques rápidos disparam; os quatro primeiros só apertam', (
    tester,
  ) async {
    final t = TapTrigger();
    expect(List.generate(5, (_) => t.tap()), [
      TapResult.press,
      TapResult.press,
      TapResult.press,
      TapResult.press,
      TapResult.fire,
    ]);
    t.release();
  });

  testWidgets('quatro toques e uma pausa não disparam', (tester) async {
    final t = TapTrigger();
    for (var i = 0; i < 4; i++) {
      t.tap();
    }
    await tester.pump(const Duration(milliseconds: 1801));
    expect(t.taps, 0);
    expect(t.tap(), TapResult.press);
    t.release();
  });

  testWidgets('cada toque reinicia o prazo de 1,8 s', (tester) async {
    final t = TapTrigger();
    final out = <TapResult>[];
    for (var i = 0; i < 5; i++) {
      out.add(t.tap());
      await tester.pump(const Duration(milliseconds: 1700));
    }
    expect(out.last, TapResult.fire);
    t.release();
  });

  testWidgets('durante a cena os toques são ignorados, mesmo uma enxurrada', (
    tester,
  ) async {
    final t = TapTrigger();
    for (var i = 0; i < 5; i++) {
      t.tap();
    }
    t.hold(const Duration(milliseconds: 2500));
    expect(List.generate(50, (_) => t.tap()).toSet(), {TapResult.ignored});
    await tester.pump(const Duration(milliseconds: 2500));
    expect(t.tap(), TapResult.press);
    t.release();
  });

  testWidgets('release libera na hora', (tester) async {
    final t = TapTrigger()..hold(const Duration(seconds: 10));
    t.release();
    expect(t.tap(), TapResult.press);
    t.release();
  });
}
