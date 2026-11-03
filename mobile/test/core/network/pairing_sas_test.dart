import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/pairing.dart';

String fixture(String name) => File('test/fixtures/pairing/$name').readAsStringSync();

final goodFp = fingerprintOfPem(fixture('good-ca.pem'));
final otherFp = fingerprintOfPem(fixture('other-ca.pem'));

List<int> unhex(String h) => [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];

/// The server side of the protocol, as `gateway/src/pairing.rs` does it: it checks the commitment and computes its digits
/// from ITS OWN CA ([serverCa]), whatever CA it hands out at `/server/ca.pem` ([servedCa]).
class FakeServer {
  FakeServer({this.servedCa, this.startReply, this.revealStatus = 204, this.name = 'Casa', this.dropFirstDone = false, this.doneStatus = 204, this.you = '192.168.1.77'});

  /// The address the server says it sees (`null`: an older server that says nothing).
  final String? you;

  /// What "done" answers: 409 plays a session that was replaced or expired.
  final int doneStatus;

  /// The first "done" dies on the wire (a connection that went stale while the person compared).
  final bool dropFirstDone;
  bool _dropped = false;

  final String? servedCa;
  final String serverCa = 'good';
  final String name;
  final int revealStatus;

  /// Replaces the answer of `/server/pair/start` (status, body) to play a server that misbehaves.
  final (int, String)? startReply;
  late final HttpServer http;
  final calls = <String>[];
  String? serverDigits;
  List<int>? _commit;
  List<int> _nonceS = const [];

  Future<FakeServer> start() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(fixture('good-server.pem')))
      ..usePrivateKeyBytes(utf8.encode(fixture('good-server.key')));
    http = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    http.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      calls.add('${req.method} ${req.uri.path}');
      final res = req.response;
      String field(String k) => body.split('\n').map((l) => l.split('=')).where((p) => p.length == 2 && p[0] == k).map((p) => p[1]).firstOrNull ?? '';
      if (req.uri.path == '/server/ca.pem') {
        res.write(servedCa ?? fixture('$serverCa-ca.pem'));
      } else if (req.uri.path == '/server/pair/start') {
        if (startReply != null) {
          res.statusCode = startReply!.$1;
          res.write(startReply!.$2);
        } else {
          _commit = unhex(field('c'));
          _nonceS = List.generate(16, (i) => i + 100);
          res.write('id=${'ab' * 16}\nn=${_nonceS.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\nname=$name\n${you == null ? '' : 'you=$you\n'}');
        }
      } else if (req.uri.path == '/server/pair/done') {
        if (dropFirstDone && !_dropped) {
          _dropped = true;
          (await res.detachSocket()).destroy();
          return;
        }
        res.statusCode = doneStatus;
      } else if (req.uri.path == '/server/pair/reveal') {
        final a = unhex(field('a'));
        // the real server refuses a number that does not match what was committed
        if (_commit == null || sha256.convert(a).toString() != _commit!.map((b) => b.toRadixString(16).padLeft(2, '0')).join()) {
          res.statusCode = 400;
        } else {
          res.statusCode = revealStatus;
          serverDigits = sasDigits(unhex(fingerprintOfPem(fixture('$serverCa-ca.pem'))), a, _nonceS);
        }
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
    return this;
  }

  int get port => http.port;
  Future<void> stop() => http.close(force: true);
}

Future<PairingResult> run(FakeServer s, MemoryPairedStore store, Future<bool> Function(SasPrompt) confirm,
        {Duration timeout = const Duration(seconds: 2), Duration confirmTimeout = const Duration(seconds: 2), int seed = 1}) =>
    pairWithDigits(host: '127.0.0.1', port: s.port, store: store, confirm: confirm, timeout: timeout, confirmTimeout: confirmTimeout, random: Random(seed));

void main() {
  test('os 6 números são os mesmos que o gateway calcula (vetor fixo conferido com o Rust)', () {
    expect(sasDigits(List.filled(32, 7), List.filled(16, 1), List.filled(16, 2)), '180115');
    expect(SasPrompt(digits: '012345', name: 'x', hostPort: 'h', expiresAt: DateTime(2030)).grouped, '012 345');
    for (var i = 0; i < 500; i++) {
      final d = sasDigits(List.filled(32, i % 256), List.filled(16, i ~/ 2), List.filled(16, 9));
      expect(d, matches(RegExp(r'^\d{6}$')));
    }
  });

  group('pairWithDigits', () {
    late FakeServer server;
    late MemoryPairedStore store;
    setUp(() => store = MemoryPairedStore());
    tearDown(() => server.stop());

    test('a pessoa confere, diz que são iguais e o servidor passa a ser confiável só com a CA dele', () async {
      server = await FakeServer().start();
      SasPrompt? shown;
      final r = await run(server, store, (p) async {
        shown = p;
        return p.digits == server.serverDigits; // what the person does: compares the two screens
      });
      expect(r, isA<Paired>());
      expect(shown!.digits, server.serverDigits);
      expect(shown!.name, 'Casa');
      final kept = await store.find('127.0.0.1:${server.port}');
      expect(kept!.fingerprint, goodFp);
      expect(server.calls, ['GET /server/ca.pem', 'POST /server/pair/start', 'POST /server/pair/reveal', 'POST /server/pair/done'],
          reason: 'the CA is downloaded before the number is revealed');
    });

    test('uma pessoa lenta: a conexão fica parada e o servidor a fecha, mas o aviso de "terminei" ainda chega', () async {
      server = await FakeServer().start();
      server.http.idleTimeout = const Duration(milliseconds: 100);
      final r = await run(server, store, (p) async {
        await Future<void>.delayed(const Duration(milliseconds: 500)); // comparing the two screens
        return p.digits == server.serverDigits;
      });
      expect(r, isA<Paired>());
      expect(server.calls.last, 'POST /server/pair/done', reason: 'the server is told, so its page clears and another device can pair');
    });

    test('se o aviso de "terminei" morre na rede, é repetido numa conexão nova', () async {
      server = await FakeServer(dropFirstDone: true).start();
      final r = await run(server, store, (p) async => p.digits == server.serverDigits);
      expect(r, isA<Paired>(), reason: 'a failed notice never undoes a pairing the person confirmed');
      expect(server.calls.where((c) => c == 'POST /server/pair/done'), hasLength(2));
    });

    test('a sessão foi substituída enquanto a pessoa comparava (409): não pareia, e pede números novos', () async {
      server = await FakeServer(doneStatus: 409).start();
      final r = await run(server, store, (p) async => true);
      expect((r as PairingFailed).reason, PairingFailure.expired);
      expect(await store.find('127.0.0.1:${server.port}'), isNull, reason: 'the confirmation was about numbers the server no longer showed');
    });

    test('o servidor não confirma o "terminei" (erro, ou nenhuma resposta): não pareia, por segurança', () async {
      for (final status in [500, 404, 400, 200, 429]) {
        server = await FakeServer(doneStatus: status).start();
        final r = await run(server, store, (p) async => true);
        expect((r as PairingFailed).reason, PairingFailure.unreachable, reason: '$status');
        expect(await store.find('127.0.0.1:${server.port}'), isNull);
        await server.stop();
      }
      server = await FakeServer().start();
    });

    test('o app fica sabendo o endereço com que o servidor o vê, e ignora o que não for endereço', () async {
      for (final (you, expected) in [('192.168.1.77', '192.168.1.77'), ('fe80::1', 'fe80::1'), (null, ''), ('<script>', ''), ('not an address', ''), ('1' * 80, '')]) {
        server = await FakeServer(you: you).start();
        late SasPrompt shown;
        await run(server, store, (p) async {
          shown = p;
          return false;
        });
        expect(shown.yourAddress, expected, reason: '$you');
        await server.stop();
      }
      server = await FakeServer().start();
    });

    test('se a pessoa diz que são diferentes, nada é guardado', () async {
      server = await FakeServer().start();
      final r = await run(server, store, (_) async => false);
      expect((r as PairingFailed).reason, PairingFailure.declined);
      expect(await store.find('127.0.0.1:${server.port}'), isNull);
    });

    test('alguém no meio entrega outra CA: os números diferem e, conferindo, ninguém é pareado', () async {
      server = await FakeServer(servedCa: fixture('other-ca.pem')).start();
      late SasPrompt shown;
      final r = await run(server, store, (p) async {
        shown = p;
        return p.digits == server.serverDigits;
      });
      expect(shown.digits, isNot(server.serverDigits), reason: 'another CA gives other digits');
      expect((r as PairingFailed).reason, PairingFailure.declined);
      expect(await store.find('127.0.0.1:${server.port}'), isNull);
      expect(otherFp, isNot(goodFp));
    });

    test('quem não responde a tempo (pessoa distraída) não pareia e os números expiram', () async {
      server = await FakeServer().start();
      final never = Completer<bool>();
      final r = await run(server, store, (_) => never.future, confirmTimeout: const Duration(milliseconds: 200));
      expect((r as PairingFailed).reason, PairingFailure.expired, reason: 'new digits are asked for, nothing is kept');
      expect(await store.find('127.0.0.1:${server.port}'), isNull);
    });

    test('outro aparelho pareando (429) e bloqueio por muitas tentativas são avisados', () async {
      server = await FakeServer(startReply: (429, '{"error":{"code":"pairing_busy"}}')).start();
      expect(((await run(server, store, (_) async => true)) as PairingFailed).reason, PairingFailure.busy);
      await server.stop();
      server = await FakeServer(startReply: (429, '{"error":{"code":"pairing_locked"}}')).start();
      expect(((await run(server, store, (_) async => true)) as PairingFailed).reason, PairingFailure.locked);
      server = await FakeServer(revealStatus: 429).start();
      expect(((await run(server, store, (_) async => true)) as PairingFailed).reason, PairingFailure.locked);
    });

    test('respostas fora do protocolo viram "protocolo", nunca um pareamento', () async {
      for (final reply in <(int, String)>[
        (200, ''),
        (200, 'id=zz\nn=00\n'),
        (200, 'id=${'ab' * 16}\nn=${'0' * 31}\n'), // short number
        (200, 'id=${'ab' * 16}\nn=${'0' * 34}\n'),
        (500, 'boom'),
        (404, 'nope'),
        (200, '\u0000\u0001garbage'),
      ]) {
        server = await FakeServer(startReply: reply).start();
        final r = await run(server, store, (_) async => true);
        expect((r as PairingFailed).reason, PairingFailure.protocol, reason: '$reply');
        expect(await store.find('127.0.0.1:${server.port}'), isNull);
        await server.stop();
      }
      server = await FakeServer().start();
    });

    test('resposta gigante é cortada em vez de lida inteira', () async {
      server = await FakeServer(startReply: (200, 'x' * 200000)).start();
      final r = await run(server, store, (_) async => true);
      expect((r as PairingFailed).reason, PairingFailure.protocol);
    });

    test('o que não é uma CA, ou sem resposta, não derruba o app', () async {
      server = await FakeServer(servedCa: 'não sou um certificado').start();
      expect(((await run(server, store, (_) async => true)) as PairingFailed).reason, PairingFailure.notACertificate);
      final port = server.port;
      await server.stop();
      final closed = await pairWithDigits(host: '127.0.0.1', port: port, store: store, confirm: (_) async => true, timeout: const Duration(seconds: 1));
      expect((closed as PairingFailed).reason, PairingFailure.unreachable);
      server = await FakeServer().start();
    });

    test('um servidor que fica mudo estoura o tempo em vez de travar a tela', () async {
      final mute = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      mute.listen((_) {}); // accepts and never speaks
      final sw = Stopwatch()..start();
      final r = await pairWithDigits(host: '127.0.0.1', port: mute.port, store: store, confirm: (_) async => true, timeout: const Duration(milliseconds: 500));
      expect((r as PairingFailed).reason, PairingFailure.unreachable);
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      await mute.close();
      server = await FakeServer().start();
    });

    test('nome do servidor com caracteres de controle ou enorme não chega à tela', () async {
      server = await FakeServer(name: 'Ca\u0007sa\u0000').start();
      late SasPrompt shown;
      await run(server, store, (p) async {
        shown = p;
        return false;
      });
      expect(shown.name, 'Casa');
      await server.stop();
      server = await FakeServer(name: 'n' * 200).start();
      await run(server, store, (p) async {
        shown = p;
        return false;
      });
      expect(shown.name, '127.0.0.1', reason: 'an absurd name is replaced by the address');
    });

    test('tentar duas vezes seguidas funciona (toque errado, recomeçar)', () async {
      server = await FakeServer().start();
      expect(await run(server, store, (_) async => false, seed: 1), isA<PairingFailed>());
      expect(await run(server, store, (p) async => p.digits == server.serverDigits, seed: 2), isA<Paired>());
    });
  });
}
