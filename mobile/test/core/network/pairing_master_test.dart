import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/pairing.dart';

import 'pairing_sas_test.dart' show FakeServer, goodFp;

String hexOf(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

final master = List.generate(10, (i) => i + 1);

void main() {
  group('o texto do código mestre', () {
    test('vetores iguais aos do gateway (Rust)', () {
      expect(formatMasterCode(master), '0410-6105-0R3G-G28A');
      expect(parseMasterCode('0410-6105-0R3G-G28A'), master);
      expect(hexOf(masterProof(master, 'pindrel-master-a', List.filled(32, 7), List.filled(16, 1), List.filled(16, 2))),
          'a32fc5e550573f5abec0ecb980ca343f29e0693d6eaed7d788c1a7d7c62aab3b');
      expect(hexOf(masterProof(master, 'pindrel-master-s', List.filled(32, 7), List.filled(16, 1), List.filled(16, 2))),
          '508f576d687b3fe4dd7dc9a9d4e0f7535e73619c281dcdc3046b95ef6201ee59');
      expect(formatMasterCode(List.filled(10, 0)), '0000-0000-0000-0000');
      expect(formatMasterCode(List.filled(10, 255)), 'ZZZZ-ZZZZ-ZZZZ-ZZZZ');
    });

    test('quem digita pode errar maiúsculas, traços, espaços e letras parecidas', () {
      final r = Random(3);
      for (var i = 0; i < 200; i++) {
        final code = List.generate(10, (_) => r.nextInt(256));
        final text = formatMasterCode(code);
        expect(text.length, 19);
        expect(parseMasterCode(text), code);
        expect(parseMasterCode(text.toLowerCase()), code);
        expect(parseMasterCode(text.replaceAll('-', ' ')), code);
        expect(parseMasterCode('  $text \n'), code);
        expect(parseMasterCode(text.replaceAll('-', '')), code, reason: 'without dashes');
      }
      expect(parseMasterCode('OOOO-OOOO-OOOO-OOOO'), parseMasterCode('0000-0000-0000-0000'));
      expect(parseMasterCode('IIII-LLLL-iiii-llll'), parseMasterCode('1111-1111-1111-1111'));
    });

    test('o que não é o código vira nulo, sem exceção', () {
      for (final bad in ['', '0000', '0000-0000-0000-000', '0000-0000-0000-00000', 'UUUU-0000-0000-0000', '0000-0000-0000-000!', '\u0000' * 16, 'ç' * 16, '😀' * 16, 'x' * 1000]) {
        expect(parseMasterCode(bad), isNull, reason: bad);
      }
    });
  });

  group('pairWithMaster', () {
    late FakeServer server;
    late MemoryPairedStore store;
    setUp(() => store = MemoryPairedStore());
    tearDown(() => server.stop());

    Future<PairingResult> pair({String? code, int seed = 1}) => pairWithMaster(
          host: '127.0.0.1',
          port: server.port,
          master: code ?? formatMasterCode(master),
          store: store,
          timeout: const Duration(seconds: 2),
          random: Random(seed),
          serverId: 'abc',
        );

    test('o código certo pareia, sem comparar nada, e guarda só a CA daquele servidor', () async {
      server = await FakeServer(master: master).start();
      final r = await pair();
      expect(r, isA<Paired>());
      final kept = (await store.find('127.0.0.1:${server.port}'))!;
      expect(kept.fingerprint, goodFp);
      expect(kept.serverId, 'abc');
      expect(server.calls, ['GET /server/ca.pem', 'POST /server/pair/master/start', 'POST /server/pair/master/finish']);
    });

    test('o código é aceito digitado de qualquer jeito', () async {
      server = await FakeServer(master: master).start();
      expect(await pair(code: '  0410 6105 0r3g g28a  '), isA<Paired>());
    });

    test('código errado: recusado e nada é guardado; o servidor nunca recebe o código, só a prova', () async {
      server = await FakeServer(master: master).start();
      final r = await pair(code: formatMasterCode(List.filled(10, 9)));
      expect((r as PairingFailed).reason, PairingFailure.badCode);
      expect(await store.all(), isEmpty);
    });

    test('um servidor que não conhece o código não consegue provar: o app recusa, mesmo que aceite a prova do app', () async {
      server = await FakeServer(master: master, masterAnswer: 'wrong').start();
      final r = await pair();
      expect((r as PairingFailed).reason, PairingFailure.badCode);
      expect(await store.all(), isEmpty, reason: 'somebody who was not given the code answered: nothing is trusted');
    });

    test('uma prova do servidor que é lixo, vazia ou do tamanho errado também é recusada', () async {
      server = await FakeServer(master: master, masterAnswer: 'garbage').start();
      expect(((await pair()) as PairingFailed).reason, PairingFailure.badCode);
      expect(await store.all(), isEmpty);
    });

    test('alguém no meio entregou outra CA: a prova do app sai sobre outra impressão digital e o servidor recusa', () async {
      server = await FakeServer(master: master, servedCa: File('test/fixtures/pairing/other-ca.pem').readAsStringSync()).start();
      final r = await pair();
      expect((r as PairingFailed).reason, PairingFailure.badCode);
      expect(await store.all(), isEmpty);
    });

    test('um código mal digitado nem chega ao servidor', () async {
      server = await FakeServer(master: master).start();
      for (final bad in ['', '123', 'UUUU-UUUU-UUUU-UUUU']) {
        final r = await pair(code: bad);
        expect((r as PairingFailed).reason, PairingFailure.badCode, reason: bad);
      }
      expect(server.calls, isEmpty, reason: 'nothing was sent for a code that is not even well formed');
    });

    test('o servidor sem código mestre (ou com outra versão) não quebra o app', () async {
      server = await FakeServer().start();
      expect(((await pair()) as PairingFailed).reason, PairingFailure.badCode);
    });

    test('servidor fora do ar ou mudo: erro simples, sem esperar para sempre', () async {
      server = await FakeServer(master: master).start();
      final port = server.port;
      await server.stop();
      final sw = Stopwatch()..start();
      final r = await pairWithMaster(host: '127.0.0.1', port: port, master: formatMasterCode(master), store: store, timeout: const Duration(seconds: 1));
      expect((r as PairingFailed).reason, PairingFailure.unreachable);
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      server = await FakeServer().start();
    });
  });
}
