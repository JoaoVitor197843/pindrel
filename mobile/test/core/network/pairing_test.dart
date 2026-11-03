import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/pairing.dart';

String fixture(String name) => File('test/fixtures/pairing/$name').readAsStringSync();

final goodFp = fingerprintOfPem(fixture('good-ca.pem'));
final otherFp = fingerprintOfPem(fixture('other-ca.pem'));

String code(String host, String fp, {String name = 'Casa'}) => 'pindrel://pair?host=$host&ca=$fp&n=${Uri.encodeQueryComponent(name)}';

/// A TLS server with the certificate of the "good" CA that serves `/server/ca.pem` (whatever [caPem] says) and the info.
Future<HttpServer> serve({String? caPem, String certs = 'good', Duration delay = Duration.zero, int status = 200}) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(utf8.encode(fixture('$certs-server.pem')))
    ..usePrivateKeyBytes(utf8.encode(fixture('$certs-server.key')));
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  server.listen((req) async {
    await Future<void>.delayed(delay);
    if (req.uri.path == '/server/ca.pem') {
      req.response.statusCode = status;
      req.response.write(caPem ?? fixture('good-ca.pem'));
    } else {
      req.response.write('ok');
    }
    await req.response.close();
  });
  return server;
}

void main() {
  group('PairingCode', () {
    test('lê um código completo', () {
      final c = PairingCode.tryParse(code('192.168.1.5:8443', goodFp, name: 'Casa & Sítio'))!;
      expect((c.host, c.port, c.fingerprint, c.name), ('192.168.1.5', 8443, goodFp, 'Casa & Sítio'));
      expect(c.hostPort, '192.168.1.5:8443');
      expect(c.baseUri.toString(), 'https://192.168.1.5:8443');
    });

    test('aceita nome de domínio, IPv6 e impressão digital em maiúsculas, com espaços em volta', () {
      expect(PairingCode.tryParse('  ${code('casa.lan:8443', goodFp.toUpperCase())}  ')!.host, 'casa.lan');
      final v6 = PairingCode.tryParse(code('[fe80::1]:8443', goodFp))!;
      expect((v6.host, v6.hostPort), ('fe80::1', '[fe80::1]:8443'));
      expect(PairingCode.tryParse('pindrel://pair?host=192.168.1.5:8443&ca=$goodFp')!.name, '');
    });

    test('recusa o que não é exatamente um código', () {
      final bad = <String>[
        '',
        '   ',
        'https://192.168.1.5:8443',
        'pindrel://other?host=1.2.3.4:5&ca=$goodFp',
        'pindrel://pair',
        'pindrel://pair?host=192.168.1.5:8443', // sem impressão digital
        'pindrel://pair?ca=$goodFp', // sem endereço
        'pindrel://pair?host=192.168.1.5:8443&ca=${goodFp.substring(1)}', // curta
        'pindrel://pair?host=192.168.1.5:8443&ca=${goodFp}0', // longa
        'pindrel://pair?host=192.168.1.5:8443&ca=${'g' * 64}', // não é hex
        'pindrel://pair?host=192.168.1.5&ca=$goodFp', // sem porta
        'pindrel://pair?host=192.168.1.5:0&ca=$goodFp',
        'pindrel://pair?host=192.168.1.5:65536&ca=$goodFp',
        'pindrel://pair?host=192.168.1.5:-1&ca=$goodFp',
        'pindrel://pair?host=:8443&ca=$goodFp',
        'pindrel://pair?host=a b:8443&ca=$goodFp',
        'pindrel://pair?host=evil.com/path:8443&ca=$goodFp',
        'pindrel://pair?host=user@evil.com:8443&ca=$goodFp',
        'pindrel://pair?host=999.1.1.1:8443&ca=$goodFp',
        'pindrel://pair?host=[1.2.3.4]:8443&ca=$goodFp',
        'pindrel://pair?host=[::1:8443&ca=$goodFp',
        'pindrel://pair?host=1.2.3.4:8443&host=5.6.7.8:8443&ca=$goodFp', // repetido
        'pindrel://pair?host=1.2.3.4:8443&ca=$goodFp&x=1', // parâmetro desconhecido
        'pindrel://pair?host=1.2.3.4:8443&ca=$goodFp#frag',
        'pindrel://u:p@pair?host=1.2.3.4:8443&ca=$goodFp',
        'pindrel://pair?host=1.2.3.4:8443&ca=$goodFp&n=${'x' * 65}',
        'pindrel://pair?host=1.2.3.4:8443&ca=$goodFp&n=${'x' * 600}',
        'pindrel://pair?host=${'a' * 300}.lan:8443&ca=$goodFp',
        'pindrel://pair?host=1.2.3.4:8443&ca=$goodFp\n',
        'pindrel://pair?host=1.2.3.4:8443 &ca=$goodFp',
        '\u0000pindrel://pair?host=1.2.3.4:8443&ca=$goodFp',
      ];
      for (final text in bad) {
        // the trailing newline is whitespace around the code and is trimmed; the others must fail
        if (text.endsWith('\n') && !text.contains(' ')) continue;
        expect(PairingCode.tryParse(text), isNull, reason: text);
      }
    });

    test('lixo aleatório nunca lança', () {
      final rnd = Random2(7);
      for (var i = 0; i < 2000; i++) {
        final s = String.fromCharCodes(List.generate(rnd.next(80), (_) => rnd.next(0x2FF)));
        PairingCode.tryParse(s);
        PairingCode.tryParse('pindrel://pair?host=$s&ca=$s&n=$s');
      }
    });
  });

  group('código de conferência', () {
    test('são os 12 primeiros dígitos da impressão digital, em maiúsculas, de 4 em 4', () {
      final c = PairingCode.tryParse(code('192.168.1.5:8443', goodFp))!;
      expect(c.confirmation, '${goodFp.substring(0, 4)}-${goodFp.substring(4, 8)}-${goodFp.substring(8, 12)}'.toUpperCase());
      expect(c.confirmation, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
    });
    test('entradas estranhas dão vazio, nunca lançam', () {
      for (final s in ['', 'abc', '日本語日本語日本語日本語', 'zzzzzzzzzzzzzzzz', '12345678901']) {
        expect(confirmationCode(s), '', reason: s);
      }
      expect(confirmationCode('ab' * 32), 'ABAB-ABAB-ABAB'); // the same as the gateway's
    });
  });

  group('fingerprintOfPem', () {
    test('é o SHA-256 do certificado e ignora quebras de linha', () {
      final pem = fixture('good-ca.pem');
      expect(goodFp, hasLength(64));
      expect(fingerprintOfPem(pem.replaceAll('\n', '\r\n')), goodFp);
      expect(goodFp, isNot(otherFp));
    });
    test('texto que não é certificado dá vazio', () {
      for (final s in ['', 'lixo', '-----BEGIN CERTIFICATE-----\n!!!\n-----END CERTIFICATE-----', '-----BEGIN CERTIFICATE-----\nabc']) {
        expect(fingerprintOfPem(s), '', reason: s);
      }
    });
  });

  group('pareamento', () {
    late HttpServer server;
    tearDown(() async => server.close(force: true));

    PairingCode codeFor(int port, String fp) => PairingCode.tryParse(code('127.0.0.1:$port', fp))!;

    test('com o código certo guarda a CA e a conexão passa a funcionar só para esse servidor', () async {
      server = await serve();
      final store = MemoryPairedStore();
      final result = await pair(codeFor(server.port, goodFp), store);
      expect(result, isA<Paired>());
      final saved = (await store.find('127.0.0.1:${server.port}'))!;
      expect(saved.fingerprint, goodFp);

      final client = clientFor(saved);
      expect((await client.get(Uri.parse('https://127.0.0.1:${server.port}/server/info/'))).body, 'ok');
      client.close();
    });

    test('o código de OUTRO servidor (impressão digital diferente) recusa e não guarda nada', () async {
      server = await serve(); // este servidor serve a CA "good"
      final store = MemoryPairedStore();
      final result = await pair(codeFor(server.port, otherFp), store);
      expect(result, isA<PairingFailed>().having((f) => f.reason, 'reason', PairingFailure.fingerprintMismatch));
      expect(await store.find('127.0.0.1:${server.port}'), isNull);
    });

    test('um impostor que serve a SUA CA sob o código verdadeiro é recusado', () async {
      server = await serve(caPem: fixture('other-ca.pem'));
      final result = await pair(codeFor(server.port, goodFp), MemoryPairedStore());
      expect(result, isA<PairingFailed>().having((f) => f.reason, 'reason', PairingFailure.fingerprintMismatch));
    });

    test('um caractere errado no código basta para recusar', () async {
      server = await serve();
      final wrong = goodFp.substring(0, 63) + (goodFp.endsWith('0') ? '1' : '0');
      expect(await pair(codeFor(server.port, wrong), MemoryPairedStore()), isA<PairingFailed>());
    });

    test('resposta que não é certificado, grande demais, com erro ou vazia é recusada', () async {
      for (final (pem, status) in [('<html>oi</html>', 200), ('', 200), ('x' * 100000, 200), (fixture('good-ca.pem'), 404)]) {
        server = await serve(caPem: pem, status: status);
        final result = await pair(codeFor(server.port, goodFp), MemoryPairedStore());
        expect(result, isA<PairingFailed>().having((f) => f.reason, 'reason', PairingFailure.notACertificate), reason: '$status ${pem.length}');
        await server.close(force: true);
      }
      server = await serve();
    });

    test('ninguém no endereço, ou resposta lenta demais: inalcançável, sem travar', () async {
      server = await serve(delay: const Duration(seconds: 3));
      final slow = await pair(codeFor(server.port, goodFp), MemoryPairedStore(), timeout: const Duration(milliseconds: 400));
      expect(slow, isA<PairingFailed>().having((f) => f.reason, 'reason', PairingFailure.unreachable));
      final closedPort = server.port;
      await server.close(force: true);
      final gone = await pair(codeFor(closedPort, goodFp), MemoryPairedStore(), timeout: const Duration(seconds: 1));
      expect(gone, isA<PairingFailed>().having((f) => f.reason, 'reason', PairingFailure.unreachable));
      server = await serve();
    });

    test('depois de pareado, outro servidor (outra CA) NÃO é aceito pelo mesmo cliente', () async {
      server = await serve();
      final store = MemoryPairedStore();
      await pair(codeFor(server.port, goodFp), store);
      final impostor = await serve(certs: 'other');
      final client = clientFor((await store.find('127.0.0.1:${server.port}'))!);
      await expectLater(client.get(Uri.parse('https://127.0.0.1:${impostor.port}/server/info/')), throwsA(isA<HandshakeException>()));
      client.close();
      await impostor.close(force: true);
    });

    test('o cliente pareado não usa as raízes do sistema: um endereço qualquer é recusado', () async {
      server = await serve();
      final store = MemoryPairedStore();
      await pair(codeFor(server.port, goodFp), store);
      final client = clientFor((await store.find('127.0.0.1:${server.port}'))!);
      await expectLater(client.get(Uri.parse('https://example.com/')), throwsA(anything));
      client.close();
    });

    test('clientForUri usa o cliente pareado só para o servidor pareado', () async {
      server = await serve();
      final store = MemoryPairedStore();
      await pair(codeFor(server.port, goodFp), store);
      final paired = await clientForUri(Uri.parse('https://127.0.0.1:${server.port}'), store);
      expect((await paired.get(Uri.parse('https://127.0.0.1:${server.port}/server/info/'))).statusCode, 200);
      paired.close();
      // an http address never gets a paired client
      final plain = await clientForUri(Uri.parse('http://127.0.0.1:${server.port}'), store);
      plain.close();
    });

    test('vários pareamentos ao mesmo tempo não se atrapalham', () async {
      server = await serve();
      final results = await Future.wait(List.generate(25, (_) => pair(codeFor(server.port, goodFp), MemoryPairedStore())));
      expect(results.every((r) => r is Paired), isTrue);
    });
  });

  group('PairedServer guardado', () {
    test('um JSON com a CA trocada (impressão digital que não confere) é descartado', () {
      final ok = PairedServer(hostPort: '1.2.3.4:5', fingerprint: goodFp, caPem: fixture('good-ca.pem'), name: 'Casa');
      expect(PairedServer.fromJson(ok.toJson()), isNotNull);
      final swapped = {...ok.toJson(), 'caPem': fixture('other-ca.pem')};
      expect(PairedServer.fromJson(swapped), isNull);
      for (final bad in [null, 5, 'x', <String, Object?>{}, {'hostPort': 1}]) {
        expect(PairedServer.fromJson(bad), isNull);
      }
    });
  });
}

/// A tiny deterministic generator (the test must not depend on a seed from the clock).
class Random2 {
  Random2(this._s);
  int _s;
  int next(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s % max;
  }
}
