import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/network/server_probe.dart';

void main() {
  final uri = Uri.parse('http://10.0.0.5:8080');

  test('qualquer resposta vale, até um erro HTTP', () async {
    Uri? asked;
    final client = MockClient((r) async {
      asked = r.url;
      return http.Response('', 404);
    });
    expect(await httpServerProbe(uri, client: client), isTrue);
    expect(asked, Uri.parse('http://10.0.0.5:8080/server/info/'));
  });

  test('erro de rede é falso', () async {
    final client = MockClient((_) async => throw http.ClientException('x'));
    expect(await httpServerProbe(uri, client: client), isFalse);
  });

  test('um corpo sem fim não é lido: a resposta basta, e chega logo', () async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => s.close(force: true));
    s.listen((req) async {
      final chunk = List.filled(64 * 1024, 120);
      try {
        for (var i = 0; i < 100000; i++) {
          req.response.add(chunk);
          await req.response.flush();
        }
      } catch (_) {
        // the app hung up
      }
    });
    final sw = Stopwatch()..start();
    expect(await httpServerProbe(Uri.parse('http://127.0.0.1:${s.port}')), isTrue);
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('sem resposta no prazo é falso', () async {
    final client = MockClient(
      (_) => Future.delayed(probeTimeout * 2, () => http.Response('', 200)),
    );
    expect(await httpServerProbe(uri, client: client), isFalse);
  });
}
