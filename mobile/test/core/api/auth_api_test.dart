import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/shared/protos/auth.pb.dart';
import 'package:http/http.dart' as http;

void main() {
  stressTests();
  test('Testa a chamada de api para o go', () async {
    var bytes = LoginInput(
      email: 'testemail@t.com',
      password: 'testpassword1223',
    );
    final response = await http.post(
      Uri.parse('http://localhost:8086/auth/login/'),
      headers: {'Content-Type': 'application/x-protobuf'},
      body: bytes.writeToBuffer(),
    );
    expect(response.statusCode, 401);
    var message = ErrorHttp.fromBuffer(response.bodyBytes);
    expect(message.code, 'invalid_credentials');
    expect(message.message, 'Invalid email or password');
  });

  test('Testa a função auxiliar para guardar e adquirir cookies', () async {
    var cookies = MemoryCookieStore();
    expect(await cookies.readAll(), isEmpty);
    await cookies.write('refresh_token', 'test-cookie');
    await cookies.write('outro', 'valor');
    expect(await cookies.readAll(), {
      'refresh_token': 'test-cookie',
      'outro': 'valor',
    });
    await cookies.delete('outro');
    expect(await cookies.readAll(), {'refresh_token': 'test-cookie'});
  });

  test('Testa o envio de cookies', () async {
    http.Request? captured;

    final mock = MockClient((request) async {
      captured = request;
      return http.Response('ok', HttpStatus.ok);
    });

    final store = MemoryCookieStore();
    await store.write(CookieNames.refreshToken, 'cookie');
    final apiClient = ApiClient(
      client: mock,
      baseUrl: 'http://abc',
      cookies: store,
    );
    var input = LoginInput(
      email: 'testemail@t.com',
      password: 'testpassword1223',
    );
    await apiClient.postProto('/login/', input);

    expect(captured!.headers['Cookie'], 'refresh_token=cookie');
    expect(captured!.url.toString(), 'http://abc/login/');
    var response = LoginInput.fromBuffer(captured!.bodyBytes);
    expect(response, input);
    expect(captured!.headers['Content-Type'], 'application/x-protobuf');
  });
  test('Testa caso os cookies sejam nulos', () async {
    http.Request? captured;

    final mock = MockClient((request) async {
      captured = request;
      return http.Response('ok', HttpStatus.ok);
    });

    final store = MemoryCookieStore();
    final apiClient = ApiClient(
      client: mock,
      baseUrl: 'http://abc',
      cookies: store,
    );
    var input = LoginInput(
      email: 'testemail@t.com',
      password: 'testpassword1223',
    );
    await apiClient.postProto('/login/', input);

    expect(captured!.headers.containsKey('cookie'), false);
  });

  test('Testa o envio de mais de um cookie', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response('ok', HttpStatus.ok);
    });
    final store = MemoryCookieStore();
    await store.write('refresh_token', 'r');
    await store.write('outro', 'o');
    final apiClient = ApiClient(
      client: mock,
      baseUrl: 'http://abc',
      cookies: store,
    );
    await apiClient.postProto('/login/', LoginInput());

    expect(captured!.headers['Cookie'], 'refresh_token=r; outro=o');
  });

  test('Testa que cookies do Set-Cookie são guardados', () async {
    final mock = MockClient((request) async {
      return http.Response(
        'ok',
        HttpStatus.ok,
        headers: {
          'set-cookie':
              'refresh_token=abc.def; Path=/; Max-Age=3600; HttpOnly; '
              'SameSite=Lax,outro=x=y; Expires=Wed, 21 Oct 2026 07:28:00 GMT',
        },
      );
    });
    final store = MemoryCookieStore();
    final apiClient = ApiClient(
      client: mock,
      baseUrl: 'http://abc',
      cookies: store,
    );
    await apiClient.postProto('/login/', LoginInput());

    expect(await store.readAll(), {'refresh_token': 'abc.def', 'outro': 'x=y'});
  });

  test('Testa que cookie limpo pelo servidor é removido (logout)', () async {
    final mock = MockClient((request) async {
      return http.Response(
        'ok',
        HttpStatus.ok,
        headers: {'set-cookie': 'refresh_token=; Path=/; Max-Age=0; HttpOnly'},
      );
    });
    final store = MemoryCookieStore();
    await store.write('refresh_token', 'abc');
    final apiClient = ApiClient(
      client: mock,
      baseUrl: 'http://abc',
      cookies: store,
    );
    await apiClient.postProto('/logout/', LoginInput());

    expect(await store.readAll(), isEmpty);
  });

  test('parseSetCookies ignora header ausente ou malformado', () {
    expect(parseSetCookies(null), isEmpty);
    expect(parseSetCookies(''), isEmpty);
    expect(parseSetCookies('HttpOnly; Secure'), isEmpty);
    final cookies = parseSetCookies('a=1; Max-Age=-1');
    expect(cookies.single.isRemoval, isTrue);
  });
}

// ---- careless use / bad connection ----
void stressTests() {
  test('erro de rede propaga e não mexe nos cookies guardados', () async {
    final store = MemoryCookieStore();
    await store.write('refresh_token', 'abc');
    final api = ApiClient(
      client: MockClient((_) async => throw const SocketException('sem rede')),
      baseUrl: 'http://abc',
      cookies: store,
    );
    await expectLater(
      api.postProto('/auth/login/', LoginInput()),
      throwsA(isA<SocketException>()),
    );
    expect(await store.readAll(), {'refresh_token': 'abc'});
  });

  test('resposta de erro (401/500) também atualiza cookies e é devolvida', () async {
    final store = MemoryCookieStore();
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response(
          '',
          HttpStatus.unauthorized,
          headers: {'set-cookie': 'refresh_token=; Max-Age=0'},
        ),
      ),
      baseUrl: 'http://abc',
      cookies: store,
    );
    await store.write('refresh_token', 'velho');
    final res = await api.postProto('/auth/refresh/', LoginInput());
    expect(res.statusCode, 401);
    expect(await store.readAll(), isEmpty);
  });

  test('Set-Cookie gigante ou com lixo não lança', () {
    expect(parseSetCookies('a=${'x' * 200000}').single.value.length, 200000);
    expect(parseSetCookies(',,,;;;===').length, lessThanOrEqualTo(1));
    expect(parseSetCookies('a=1; Max-Age=abc').single.maxAge, isNull);
    expect(parseSetCookies('   ,   '), isEmpty);
  });

  test('Max-Age positivo não é remoção; valor vazio é', () {
    expect(parseSetCookies('a=1; Max-Age=60').single.isRemoval, isFalse);
    expect(parseSetCookies('a=; Max-Age=60').single.isRemoval, isTrue);
  });

  test('o corpo vai como protobuf mesmo vazio, e chamadas seguidas não se misturam', () async {
    final bodies = <int>[];
    final api = ApiClient(
      client: MockClient((req) async {
        bodies.add(req.bodyBytes.length);
        return http.Response('', HttpStatus.ok);
      }),
      baseUrl: 'http://abc',
      cookies: MemoryCookieStore(),
    );
    await Future.wait([
      api.postProto('/a/', LoginInput()),
      api.postProto('/b/', LoginInput(email: 'a@b.c', password: 'x' * 72)),
    ]);
    expect(bodies..sort(), [0, greaterThan(70)]);
  });
}
