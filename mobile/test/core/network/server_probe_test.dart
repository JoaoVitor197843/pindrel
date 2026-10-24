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

  test('sem resposta no prazo é falso', () async {
    final client = MockClient(
      (_) => Future.delayed(probeTimeout * 2, () => http.Response('', 200)),
    );
    expect(await httpServerProbe(uri, client: client), isFalse);
  });
}
