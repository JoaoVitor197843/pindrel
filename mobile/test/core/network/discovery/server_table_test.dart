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
}
