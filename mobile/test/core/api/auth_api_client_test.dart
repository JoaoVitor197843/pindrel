import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/core/api/auth_api.dart';
import 'package:mobile/core/api/auth_messages.dart';
import 'package:mobile/shared/protos/auth.pb.dart';

AuthApi apiOver(MockClientHandler handler, {CookieStore? cookies}) =>
    AuthApi(ApiClient(client: MockClient(handler), baseUrl: 'http://srv', cookies: cookies ?? MemoryCookieStore()));

http.Response proto(List<int> bytes, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response.bytes(bytes, status, headers: headers);

http.Response error(int status, String code, [Map<String, String> headers = const {}]) =>
    proto(ErrorHttp(code: code, message: 'x').writeToBuffer(), status, headers);

Future<AuthApiError> failure(Future<Object?> call) async {
  try {
    await call;
  } on AuthApiError catch (e) {
    return e;
  }
  fail('should have failed');
}

void main() {
  group('AuthApi', () {
    test('login sends protobuf to /auth/login/, with session_only, and reads the tokens', () async {
      late http.Request seen;
      final api = apiOver((r) async {
        seen = r;
        return proto(LoginRefreshResponse(accessToken: 'tok', expiresIn: 900).writeToBuffer());
      });
      final t = await api.login('a@b.c', 'senha123', sessionOnly: true);
      expect(t.accessToken, 'tok');
      expect(t.expiresIn, 900);
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://srv/auth/login/');
      expect(seen.headers['Content-Type'], 'application/x-protobuf');
      expect(seen.headers['Accept'], 'application/x-protobuf');
      final body = LoginInput.fromBuffer(seen.bodyBytes);
      expect((body.email, body.password, body.sessionOnly), ('a@b.c', 'senha123', true));
    });

    test('the refresh cookie from login is stored and sent by refresh, with no body', () async {
      final cookies = MemoryCookieStore();
      final api = apiOver((r) async {
        if (r.url.path == '/auth/login/') {
          return proto(LoginRefreshResponse(accessToken: 't1', expiresIn: 60).writeToBuffer(), 200, {'set-cookie': 'refresh_token=abc; Path=/; HttpOnly'});
        }
        expect(r.headers['Cookie'], 'refresh_token=abc');
        expect(r.bodyBytes, isEmpty);
        return proto(LoginRefreshResponse(accessToken: 't2', expiresIn: 60).writeToBuffer());
      }, cookies: cookies);
      await api.login('a@b.c', 'x', sessionOnly: false);
      expect((await api.refresh()).accessToken, 't2');
    });

    test('me carries the bearer token and reads the account', () async {
      final api = apiOver((r) async {
        expect(r.method, 'GET');
        expect(r.headers['Authorization'], 'Bearer tok');
        return proto(UserSummary(id: 'u1', email: 'a@b.c', username: 'ana').writeToBuffer());
      });
      expect(await api.me('tok'), const Account(id: 'u1', email: 'a@b.c', username: 'ana'));
    });

    test('register reads the created user', () async {
      final api = apiOver((r) async => proto(RegisterResponse(user: UserSummary(id: 'u', email: 'e', username: 'n')).writeToBuffer(), 201));
      expect((await api.register('e', 'n', 'senha123')).id, 'u');
    });

    test('logout answers 204 and clears the cookie', () async {
      final cookies = MemoryCookieStore();
      await cookies.write('refresh_token', 'abc');
      final api = apiOver((r) async => http.Response('', 204, headers: {'set-cookie': 'refresh_token=; Path=/; Max-Age=0'}), cookies: cookies);
      await api.logout('tok');
      expect(await cookies.readAll(), isEmpty);
    });

    test('an error answer becomes its code, status and Retry-After (capped at a minute)', () async {
      final e = await failure(apiOver((_) async => error(503, 'server_busy', {'retry-after': '5'})).login('a@b.c', 'x', sessionOnly: false));
      expect((e.status, e.code, e.retryAfter), (503, 'server_busy', const Duration(seconds: 5)));
      final big = await failure(apiOver((_) async => error(503, 'server_busy', {'retry-after': '9999'})).login('a@b.c', 'x', sessionOnly: false));
      expect(big.retryAfter, const Duration(seconds: 60));
    });

    test('an error that is not protobuf (a proxy page, an empty body) keeps only the status', () async {
      final html = await failure(apiOver((_) async => http.Response('<html>502</html>', 502)).refresh());
      expect((html.status, html.code), (502, 'http_error'));
      final empty = await failure(apiOver((_) async => http.Response('', 429)).refresh());
      expect((empty.status, empty.code), (429, 'http_error'));
      expect(messageFor(empty, FormMode.login), tooManyMessage);
    });

    test('no connection, a TLS failure and a slow server have their own codes', () async {
      expect((await failure(apiOver((_) async => throw const SocketException('down')).refresh())).code, 'network');
      expect((await failure(apiOver((_) async => throw http.ClientException('reset')).refresh())).code, 'network');
      expect((await failure(apiOver((_) async => throw const HandshakeException('bad cert')).refresh())).code, 'tls');
      expect((await failure(apiOver((_) async => throw TimeoutException('slow')).refresh())).code, 'timeout');
    });

    test('a success that is not a Pindrel answer is bad_reply, never a crash', () async {
      for (final bytes in [Uint8List(0), Uint8List.fromList([0xff, 0xff, 0xff]), Uint8List.fromList('<html>'.codeUnits)]) {
        final e = await failure(apiOver((_) async => proto(bytes)).login('a@b.c', 'x', sessionOnly: false));
        expect(e.code, 'bad_reply', reason: '$bytes');
      }
      expect((await failure(apiOver((_) async => proto(Uint8List(0))).me('t'))).code, 'bad_reply');
      expect((await failure(apiOver((_) async => proto(Uint8List(0), 201)).register('e', 'n', 'p'))).code, 'bad_reply');
    });

    test('an answer over 64 KiB is dropped as bad_reply', () async {
      final e = await failure(apiOver((_) async => proto(Uint8List(70 * 1024))).refresh());
      expect(e.code, 'bad_reply');
    });

    test('a long answer streamed with no declared size is cut off too', () async {
      final client = MockClient.streaming((r, _) async => http.StreamedResponse(Stream.fromIterable([for (var i = 0; i < 100; i++) Uint8List(1024)]), 200));
      final api = AuthApi(ApiClient(client: client, baseUrl: 'http://srv', cookies: MemoryCookieStore()));
      expect((await failure(api.refresh())).code, 'bad_reply');
    });
  });

  group('messages', () {
    String m(int status, String code, [FormMode mode = FormMode.login]) => messageFor(AuthApiError(status, code), mode);

    test('every code the backend sends has a plain Portuguese message', () {
      expect(m(401, 'invalid_credentials'), 'E-mail ou senha incorretos.');
      expect(m(409, 'email_already_exists'), contains('já está cadastrado'));
      expect(m(403, 'registration_disabled'), contains('desativados'));
      expect(m(503, 'server_busy'), contains('ocupado'));
      expect(m(413, 'payload_too_large'), contains('grandes demais'));
      expect(m(0, 'network'), contains('conexão'));
      expect(m(0, 'tls'), contains('Pareie'));
      expect(m(0, 'timeout'), contains('demorou'));
      expect(m(200, 'bad_reply'), contains('Pindrel'));
    });

    test('validation and weak passwords read by the mode', () {
      expect(m(422, 'validation_failed', FormMode.register), contains('3 a 32'));
      expect(m(422, 'validation_failed'), 'Confira o e-mail e a senha.');
      expect(m(400, 'invalid_input', FormMode.register), contains('fraca'));
      expect(m(400, 'invalid_input'), 'Confira o e-mail e a senha.');
    });

    test('unknown codes fall back by status, and never show English', () {
      expect(m(429, 'rate_limited'), tooManyMessage);
      expect(m(502, 'x'), contains('problema'));
      expect(m(418, 'x'), 'Algo deu errado. Tente de novo.');
      expect(messageFor(StateError('x'), FormMode.login), 'Algo deu errado. Tente de novo.');
    });
  });

  group('validateAuth', () {
    FieldProblem? v(FormMode mode, {String email = 'a@b.c', String username = 'ana', String password = 'senha123'}) =>
        validateAuth(mode, email: email, username: username, password: password);

    test('accepts a good login and a good sign-up', () {
      expect(v(FormMode.login), isNull);
      expect(v(FormMode.register), isNull);
      expect(v(FormMode.login, email: '  a@b.c  '), isNull);
    });

    test('e-mail: empty, spaces inside, no at sign, too long', () {
      for (final e in ['', '   ', 'a b@c.d', 'abc', '@', 'a@', '@b', '${'a' * 252}@b.c']) {
        expect(v(FormMode.login, email: e)?.field, AuthField.email, reason: e);
      }
    });

    test('login only needs a password, not a long one', () {
      expect(v(FormMode.login, password: '1'), isNull);
      expect(v(FormMode.login, password: '')?.field, AuthField.password);
    });

    test('sign-up: username 3-32 characters (emoji count once), password 8-72 bytes', () {
      expect(v(FormMode.register, username: 'ab')?.field, AuthField.username);
      expect(v(FormMode.register, username: '  ab  ')?.field, AuthField.username);
      expect(v(FormMode.register, username: 'a' * 33)?.field, AuthField.username);
      expect(v(FormMode.register, username: '🚀🚀🚀'), isNull);
      expect(v(FormMode.register, password: '1234567')?.field, AuthField.password);
      expect(v(FormMode.register, password: 'a' * 73)?.field, AuthField.password);
      expect(v(FormMode.register, password: 'a' * 72), isNull);
      // 4 emoji = 16 bytes: long enough though only 4 characters; 19 of them are 76 bytes: too long
      expect(v(FormMode.register, password: '🚀🚀🚀🚀'), isNull);
      expect(v(FormMode.register, password: '🚀' * 19)?.field, AuthField.password);
    });
  });
}
