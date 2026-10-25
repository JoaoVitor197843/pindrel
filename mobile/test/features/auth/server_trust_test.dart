import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/data/server_trust.dart';

class BrokenStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => throw Exception('sem keyring');

  @override
  Future<void> write(String key, String value) async =>
      throw Exception('sem keyring');
}

void main() {
  late MemoryKeyValueStore store;
  late ServerTrust trust;

  Future<ServerTrust> fresh() async {
    final t = ServerTrust(store);
    await t.load();
    return t;
  }

  setUp(() async {
    store = MemoryKeyValueStore();
    trust = await fresh();
  });

  test('um nome nunca aberto é desconhecido', () {
    expect(trust.trustOf('Casa', 'abc'), Trust.unknown);
    expect(trust.trustOf('Casa', ''), Trust.unknown);
  });

  test('o mesmo id sob o mesmo nome é o mesmo servidor', () async {
    await trust.remember('Casa', 'abc');
    expect(trust.trustOf('Casa', 'abc'), Trust.same);
  });

  test('outro id mudou, e sem id onde havia um também', () async {
    await trust.remember('Casa', 'abc');
    expect(trust.trustOf('Casa', 'xyz'), Trust.changed);
    expect(trust.trustOf('Casa', ''), Trust.changed);
    expect(trust.trustOf('Escritório', 'xyz'), Trust.unknown);
  });

  test('servidor que não tinha id e passa a ter não gera aviso', () async {
    await trust.remember('Velho', '');
    expect(trust.trustOf('Velho', 'abc'), Trust.unknown);
    expect(trust.trustOf('Velho', ''), Trust.same);
  });

  test('lembrar de novo troca o id', () async {
    await trust.remember('Casa', 'abc');
    await trust.remember('Casa', 'xyz');
    expect(trust.trustOf('Casa', 'xyz'), Trust.same);
    expect(trust.trustOf('Casa', 'abc'), Trust.changed);
  });

  test('o que foi lembrado sobrevive a reabrir o app', () async {
    await trust.remember('Casa', 'abc');
    final again = await fresh();
    expect(again.trustOf('Casa', 'abc'), Trust.same);
    expect(again.trustOf('Casa', 'zzz'), Trust.changed);
  });

  test('guarda no máximo 64 nomes e esquece o mais antigo', () async {
    for (var i = 0; i < 100; i++) {
      await trust.remember('S$i', 'id$i');
    }
    expect(trust.trustOf('S99', 'id99'), Trust.same);
    expect(trust.trustOf('S0', 'qualquer'), Trust.unknown);
    final again = await fresh();
    expect(again.trustOf('S36', 'id36'), Trust.same);
    expect(again.trustOf('S35', 'id35'), Trust.unknown);
  });

  test('nomes estranhos não quebram nada', () async {
    for (final name in ['__proto__', '', ' ', '😀' * 40, 'a"b\\n', 'ü']) {
      await trust.remember(name, 'id1');
      expect(trust.trustOf(name, 'id1'), Trust.same, reason: name);
      expect(trust.trustOf(name, 'id2'), Trust.changed, reason: name);
    }
  });

  for (final raw in [
    'não é json {',
    '{"a":1}',
    '[1, null, ["a"], ["a", 2], {"x":1}]',
    '',
  ]) {
    test('armazenamento corrompido ($raw) é ignorado', () async {
      store.data[ServerTrust.storageKey] = raw;
      final t = await fresh();
      expect(t.trustOf('Casa', 'abc'), Trust.unknown);
      await t.remember('Casa', 'abc');
      expect(t.trustOf('Casa', 'abc'), Trust.same);
    });
  }

  test(
    'sem keyring (leitura e escrita falham) nada lança e ninguém é avisado',
    () async {
      final t = ServerTrust(BrokenStore());
      await t.load();
      await t.remember('Casa', 'abc');
      expect(
        t.trustOf('Casa', 'abc'),
        Trust.same,
        reason: 'ao menos nesta sessão',
      );
      expect(t.trustOf('Outro', 'x'), Trust.unknown);
    },
  );
}
