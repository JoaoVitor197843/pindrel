import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/server_table.dart';

import '../../../support/discovery_fakes.dart';

void main() {
  test('começa vazia', () {
    final t = ServerTable();
    expect(t.isEmpty, isTrue);
    expect(t.snapshot, isEmpty);
  });

  test('upsert insere, não repete o que não mudou e substitui o que mudou', () {
    final t = ServerTable();
    final a = server('A', addresses: ['10.0.0.1']);
    expect(t.upsert(a), isTrue);
    expect(t.upsert(a), isFalse, reason: 'igual: nada mudou');
    expect(t.upsert(server('A', addresses: ['10.0.0.9'])), isTrue);
    expect(t.snapshot, [
      server('A', addresses: ['10.0.0.9']),
    ]);
  });

  test('remove diz se havia o servidor', () {
    final t = ServerTable()..upsert(server('A'));
    expect(t.remove('B'), isFalse);
    expect(t.remove('A'), isTrue);
    expect(t.isEmpty, isTrue);
  });

  test('a lista sai ordenada por nome, sem diferenciar maiúsculas', () {
    final t = ServerTable()
      ..upsert(server('casa'))
      ..upsert(server('Zeta'))
      ..upsert(server('Alfa'));
    expect(t.snapshot.map((s) => s.name), ['Alfa', 'casa', 'Zeta']);
  });

  test('a lista devolvida não pode ser alterada por fora', () {
    final t = ServerTable()..upsert(server('A'));
    expect(() => t.snapshot.add(server('B')), throwsUnsupportedError);
  });

  group('perdidos e teto', () {
    var now = DateTime(2026);
    ServerTable make({int max = 3}) =>
        ServerTable(maxServers: max, clock: () => now);
    setUp(() => now = DateTime(2026));

    test('perdido segue na lista até o prazo; ser visto apaga a marca', () {
      final t = make()..upsert(server('A'));
      expect(t.markLost('A'), isTrue);
      expect(t.markLost('B'), isFalse);
      expect(t.hasLost, isTrue);
      now = now.add(const Duration(seconds: 9));
      expect(t.expire(const Duration(seconds: 10)), isFalse);
      t.upsert(server('A')); // came back
      expect(t.hasLost, isFalse);
      now = now.add(const Duration(seconds: 60));
      expect(t.expire(const Duration(seconds: 10)), isFalse);
      expect(t.snapshot, hasLength(1));
    });

    test('marcar de novo não adia o prazo; vencido, sai', () {
      final t = make()..upsert(server('A'));
      t.markLost('A');
      now = now.add(const Duration(seconds: 6));
      t.markLost('A');
      now = now.add(const Duration(seconds: 6));
      expect(t.expire(const Duration(seconds: 10)), isTrue);
      expect(t.isEmpty, isTrue);
      expect(t.hasLost, isFalse);
    });

    test('cheia, ignora nomes novos mas atualiza os conhecidos', () {
      final t = make(max: 2)
        ..upsert(server('A'))
        ..upsert(server('B'));
      expect(t.upsert(server('C')), isFalse);
      expect(t.snapshot.map((s) => s.name), ['A', 'B']);
      expect(t.upsert(server('A', addresses: ['10.9.9.9'])), isTrue);
    });

    test('recusa nome e host grandes demais', () {
      final t = make();
      expect(t.upsert(server('N' * 65)), isFalse);
      expect(t.isEmpty, isTrue);
    });
  });
}
