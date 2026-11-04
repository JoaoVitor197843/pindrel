import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'live_server.dart';

String fixture(String name) => File('test/fixtures/pairing/$name').readAsStringSync();

/// A server that answers like the gateway does on its plain port, with the behaviour the test asks for.
Future<HttpServer> plainPort({String? tlsPort, int optionsStatus = 204, String? ca, bool infoWorks = true}) async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    final res = req.response;
    if (req.uri.path == '/server/info/' && infoWorks) {
      if (tlsPort != null) res.headers.set('x-pindrel-tls', tlsPort);
      res.headers.set('x-pindrel-id', 'abc');
    } else if (req.uri.path == '/server/ca.pem' && ca != null) {
      res.write(ca);
    } else if (req.method == 'OPTIONS') {
      res.statusCode = optionsStatus;
    } else {
      res.statusCode = 404;
    }
    await res.close();
  });
  return s;
}

void main() {
  test('nada respondendo: "none", sem exceção e sem esperar muito', () async {
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close(force: true);
    final sw = Stopwatch()..start();
    final live = await findLiveServer(host: '127.0.0.1', port: port);
    expect(live.mode, LiveMode.none);
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('um servidor mudo é "none" depois do limite', () async {
    final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    silent.listen((_) {}); // accepts, never answers
    addTearDown(() => silent.close(force: true));
    final live = await findLiveServer(host: '127.0.0.1', port: silent.port, timeout: const Duration(milliseconds: 300));
    expect(live.mode, LiveMode.none);
  });

  test('outro programa na porta (responde 404 ou erro em /server/info/): "none", não é o servidor', () async {
    for (final status in [404, 403, 500, 301]) {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) async {
        req.response.statusCode = status;
        await req.response.close();
      });
      expect((await findLiveServer(host: '127.0.0.1', port: s.port)).mode, LiveMode.none, reason: '$status');
      await s.close(force: true);
    }
  });

  test('sem TLS: HTTP puro, usando a mesma porta', () async {
    final s = await plainPort();
    addTearDown(() => s.close(force: true));
    final live = await findLiveServer(host: '127.0.0.1', port: s.port);
    expect(live.mode, LiveMode.plain);
    expect(live.base, Uri.parse('http://127.0.0.1:${s.port}'));
  });

  test('com TLS, mas HTTP_MODE=full (a porta simples aceita tudo): continua HTTP puro', () async {
    final s = await plainPort(tlsPort: '8443', optionsStatus: 204);
    addTearDown(() => s.close(force: true));
    expect((await findLiveServer(host: '127.0.0.1', port: s.port)).mode, LiveMode.plain);
  });

  test('um valor que não é porta no cabeçalho de TLS é ignorado (HTTP puro)', () async {
    for (final bad in ['', 'abc', '0', '65536', '-1']) {
      final s = await plainPort(tlsPort: bad);
      expect((await findLiveServer(host: '127.0.0.1', port: s.port)).mode, LiveMode.plain, reason: bad);
      await s.close(force: true);
    }
  });

  test('HTTP_MODE=redirect (a porta simples recusa com 426): vai por HTTPS, confiando na CA que o servidor entrega', () async {
    // the secure side: a TLS server whose certificate the "good" CA signed
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(fixture('good-server.pem')))
      ..usePrivateKeyBytes(utf8.encode(fixture('good-server.key')));
    final secure = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    secure.listen((req) async {
      req.response.write('ok');
      await req.response.close();
    });
    addTearDown(() => secure.close(force: true));
    final s = await plainPort(tlsPort: '${secure.port}', optionsStatus: 426, ca: fixture('good-ca.pem'));
    addTearDown(() => s.close(force: true));

    final live = await findLiveServer(host: '127.0.0.1', port: s.port);
    addTearDown(live.close);
    expect(live.mode, LiveMode.secure);
    expect(live.base, Uri.parse('https://127.0.0.1:${secure.port}'));
    // and the client it hands out really talks to that server (it trusts the CA, and only that one)
    final r = await live.client.get(live.base.resolve('/'));
    expect(r.body, 'ok');
  });

  test('426 mas sem uma CA utilizável: "none", porque não há como falar com a API', () async {
    for (final ca in <String?>[null, 'isto não é um certificado']) {
      final s = await plainPort(tlsPort: '8443', optionsStatus: 426, ca: ca);
      expect((await findLiveServer(host: '127.0.0.1', port: s.port)).mode, LiveMode.none, reason: '$ca');
      await s.close(force: true);
    }
  });

  test('o cliente do modo seguro recusa um servidor com outra CA (não é "confiar em tudo")', () async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(fixture('other-server.pem')))
      ..usePrivateKeyBytes(utf8.encode(fixture('other-server.key')));
    final impostor = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    impostor.listen((req) async {
      req.response.write('x');
      await req.response.close();
    });
    addTearDown(() => impostor.close(force: true));
    final s = await plainPort(tlsPort: '${impostor.port}', optionsStatus: 426, ca: fixture('good-ca.pem'));
    addTearDown(() => s.close(force: true));
    final live = await findLiveServer(host: '127.0.0.1', port: s.port);
    addTearDown(live.close);
    expect(live.mode, LiveMode.secure);
    await expectLater(live.client.get(live.base.resolve('/')), throwsA(anything));
  });
}
