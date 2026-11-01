import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/restart_policy.dart';

void main() {
  test('a espera dobra a cada reinício e para no teto', () {
    final p = RestartPolicy(
      base: const Duration(seconds: 15),
      max: const Duration(minutes: 5),
    );
    final seen = <int>[];
    for (var i = 0; i < 8; i++) {
      seen.add(p.delay.inSeconds);
      p.restarted();
    }
    expect(seen, [15, 30, 60, 120, 240, 300, 300, 300]);
  });

  test('achar algo (ou voltar ao primeiro plano) recomeça do início', () {
    final p = RestartPolicy()
      ..restarted()
      ..restarted();
    expect(p.delay, const Duration(seconds: 60));
    p.reset();
    expect(p.delay, const Duration(seconds: 15));
  });

  test('milhares de reinícios não estouram nem passam do teto', () {
    final p = RestartPolicy(
      base: const Duration(milliseconds: 1),
      max: const Duration(minutes: 5),
    );
    for (var i = 0; i < 100000; i++) {
      p.restarted();
    }
    expect(p.delay, const Duration(minutes: 5));
  });

  test('teto menor que a base vale como teto', () {
    final p = RestartPolicy(
      base: const Duration(seconds: 15),
      max: const Duration(seconds: 5),
    );
    expect(p.delay, const Duration(seconds: 5));
  });

  group('erros', () {
    test('o primeiro início mostra o erro na hora', () {
      expect(RestartPolicy().failed(surfaceNow: true), isTrue);
    });

    test('erro de reinício só aparece na terceira falha seguida, uma vez', () {
      final p = RestartPolicy();
      expect(
        [for (var i = 0; i < 6; i++) p.failed()],
        [false, false, true, false, false, false],
      );
    });

    test('um início que deu certo zera a contagem', () {
      final p = RestartPolicy();
      p.failed();
      p.failed();
      p.succeeded();
      expect(p.failed(), isFalse);
      expect(p.failed(), isFalse);
      expect(p.failed(), isTrue);
    });
  });
}
