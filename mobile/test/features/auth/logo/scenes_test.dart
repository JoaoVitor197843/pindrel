import 'dart:math';
import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/logo/anim.dart';
import 'package:mobile/features/auth/presentation/logo/scenes.dart';
import 'package:mobile/features/auth/presentation/logo/season.dart';
import 'package:mobile/features/auth/presentation/logo/stage.dart';
import 'package:mobile/features/auth/presentation/logo/svg.dart';

void main() {
  group('Anim', () {
    test('interpola, respeita atraso e fill', () {
      final a = Anim([fr(0), fr(1, tx: 100, op: 1)], dur: 100, delay: 50);
      expect(a.sample(0), isNull);
      expect(a.sample(100)!.tf!.tx, closeTo(50, .001));
      expect(a.sample(200), isNull);
      final both = Anim(
        [fr(0), fr(1, tx: 100)],
        dur: 100,
        delay: 50,
        fill: Fill.both,
      );
      expect(both.sample(0)!.tf!.tx, 0);
      expect(both.sample(999)!.tf!.tx, 100);
    });

    test('alternate e iterações', () {
      final a = Anim([fr(0), fr(1, tx: 10)], dur: 100, iters: 2, alt: true);
      expect(a.sample(50)!.tf!.tx, closeTo(5, .001));
      expect(a.sample(150)!.tf!.tx, closeTo(5, .001)); // voltando
      expect(a.sample(100)!.tf!.tx, closeTo(10, .001));
    });

    test('easing por segmento', () {
      final a = Anim([fr(0, e: Curves.easeIn), fr(1, tx: 100)], dur: 100);
      expect(a.sample(50)!.tf!.tx, lessThan(50));
    });
  });

  group('svg', () {
    test('lê caminhos absolutos, relativos e ids', () {
      final s = parseSvg(
        '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor"><g id="a"><path d="M12 2v20M3.3 7l17.4 10"/></g><circle class="c" cx="5" cy="5" r="2" fill="#fff"/></svg>',
      );
      expect(s['a'].items, hasLength(1));
      expect(s.classes['c'], hasLength(1));
      final b = (s['a'].items.first as dynamic).path.getBounds() as Rect;
      expect(b.height, closeTo(20, .001));
    });

    test('texto fora do subconjunto falha alto, não em silêncio', () {
      expect(
        () => parsePathData('M0 0 A5 5 0 0 1 10 10'),
        throwsFormatException,
      );
    });
  });

  group('cenas', () {
    for (final theme in LogoTheme.values) {
      test('${theme.name}: monta e desenha do início ao fim sem erro', () {
        final scene = LogoScene(theme, stageWidth: 388, random: Random(1));
        expect(scene.length, greaterThan(1500));
        expect(scene.length, lessThan(4000));
        final painter = LogoStagePainter(
          scene,
          const AlwaysStoppedAnimation(0),
        );
        final total = logoStageDuration(scene);
        for (var t = 0.0; t <= total + 100; t += 40) {
          final rec = PictureRecorder();
          painter.paintAt(Canvas(rec), t);
          rec.endRecording().dispose();
        }
      });

      test(
        '${theme.name}: vale em tela estreita e com sementes diferentes',
        () {
          for (var seed = 0; seed < 5; seed++) {
            final scene = LogoScene(
              theme,
              stageWidth: 120,
              random: Random(seed),
            );
            final painter = LogoStagePainter(
              scene,
              const AlwaysStoppedAnimation(0),
            );
            final rec = PictureRecorder();
            painter.paintAt(Canvas(rec), scene.length / 2);
            rec.endRecording().dispose();
          }
        },
      );
    }

    test('tudo termina antes do fim do palco: nada fica para trás', () {
      for (final theme in LogoTheme.values) {
        final scene = LogoScene(theme, stageWidth: 388, random: Random(2));
        for (final a in [...scene.under, ...scene.over]) {
          expect(a.end, lessThanOrEqualTo(scene.runtime), reason: theme.name);
        }
      }
    });
  });
}
