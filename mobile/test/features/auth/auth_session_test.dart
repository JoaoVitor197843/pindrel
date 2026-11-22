import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api/auth_api.dart';
import 'package:mobile/features/auth/data/auth_session.dart';
import 'package:mobile/features/auth/data/server_trust.dart';

import '../../support/fake_auth_server.dart';

final home = Uri.parse('http://192.168.0.5:8080');

({FakeAuthServer server, MemoryKeyValueStore store, AuthSession session}) setup({int expiresIn = 900, Duration minRenew = const Duration(seconds: 5)}) {
  final server = FakeAuthServer(expiresIn: expiresIn)..accounts['ana@casa.local'] = (id: 'id-1', username: 'ana', password: 'senha1234');
  final store = MemoryKeyValueStore();
  final session = AuthSession(store: store, apiFactory: server.factory, minRenew: minRenew, retryEvery: const Duration(milliseconds: 50));
  addTearDown(session.dispose);
  return (server: server, store: store, session: session);
}

void main() {
  group('login', () {
    test('signs in, keeps the account and the server, and writes the note when "Manter conectado"', () async {
      final t = setup();
      final user = await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      expect(user.username, 'ana');
      expect(t.session.status, AuthStatus.signedIn);
      expect(t.session.server, home);
      final note = jsonDecode(t.store.data[AuthSession.storageKey]!) as Map;
      expect(note['server'], 'http://192.168.0.5:8080');
      expect(note['id'], 'id-1');
      expect((note['cookies'] as Map)['refresh_token'], 'cookie-id-1');
    });

    test('without "Manter conectado" nothing reaches the disk, and the server was told', () async {
      final t = setup();
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: false);
      expect(t.session.status, AuthStatus.signedIn);
      expect(t.store.data[AuthSession.storageKey] ?? '', isEmpty);
      expect(await t.session.remembered, isFalse);
    });

    test('a wrong password leaves the session out and keeps the error code', () async {
      final t = setup();
      await expectLater(
        t.session.login(home, 'ana@casa.local', 'errada', keepSignedIn: true),
        throwsA(isA<AuthApiError>().having((e) => e.code, 'code', 'invalid_credentials')),
      );
      expect(t.session.status, AuthStatus.out);
      expect(t.session.user, isNull);
    });

    test('a failure of /auth/me/ after a good login is a failed login, not half a session', () async {
      final t = setup();
      t.server.overrides['/auth/me/'] = (_) => throw Exception('dropped');
      await expectLater(t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true), throwsA(anything));
      expect(t.session.status, AuthStatus.out);
      expect(t.store.data[AuthSession.storageKey], isNull);
    });

    test('a sign-out while the login is in flight wins: the late answer cannot bring the session back', () async {
      final t = setup();
      t.server.gate = Completer();
      final pending = t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      await Future<void>.delayed(Duration.zero);
      final out = t.session.logout();
      t.server.gate!.complete();
      await out;
      await expectLater(pending, throwsA(isA<AuthApiError>().having((e) => e.code, 'code', 'cancelled')));
      expect(t.session.status, AuthStatus.out);
    });

    test('register creates the account and does not sign in', () async {
      final t = setup();
      final user = await t.session.register(home, 'bia@casa.local', 'bia', 'outrasenha1');
      expect(user.username, 'bia');
      expect(t.session.status, AuthStatus.out);
      await expectLater(t.session.register(home, 'bia@casa.local', 'bia', 'x'), throwsA(isA<AuthApiError>().having((e) => e.code, 'code', 'email_already_exists')));
    });

    test('two accounts one after the other never mix', () async {
      final t = setup();
      t.server.accounts['bia@casa.local'] = (id: 'id-2', username: 'bia', password: 'senha4321');
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      await t.session.logout();
      await t.session.login(home, 'bia@casa.local', 'senha4321', keepSignedIn: true);
      expect(t.session.user!.id, 'id-2');
      expect((jsonDecode(t.store.data[AuthSession.storageKey]!) as Map)['id'], 'id-2');
    });
  });

  group('restore', () {
    test('with nothing kept it does nothing and asks nothing', () async {
      final t = setup();
      expect(await t.session.restore(), isFalse);
      expect(t.server.requests, isEmpty);
    });

    test('turns the stored cookie back into a session', () async {
      final t = setup();
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      final again = AuthSession(store: t.store, apiFactory: t.server.factory);
      addTearDown(again.dispose);
      expect(await again.restore(), isTrue);
      expect(again.user!.username, 'ana');
      expect(again.server, home);
      expect(again.status, AuthStatus.signedIn);
    });

    test('a refusal forgets the note; no network keeps it for the next start', () async {
      final t = setup();
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);

      t.server.overrides['/auth/refresh/'] = (_) => throw Exception('offline');
      final offline = AuthSession(store: t.store, apiFactory: t.server.factory);
      addTearDown(offline.dispose);
      expect(await offline.restore(), isFalse);
      expect(offline.status, AuthStatus.out);
      expect(await offline.remembered, isTrue);

      t.server.overrides.clear();
      t.server.cookieValid = false;
      final refused = AuthSession(store: t.store, apiFactory: t.server.factory);
      addTearDown(refused.dispose);
      expect(await refused.restore(), isFalse);
      expect(await refused.remembered, isFalse);
    });

    test('a damaged or hostile note is ignored, never trusted', () async {
      for (final raw in ['not json', '[]', '{"server":"ftp://x","id":"a","username":"b"}', '{"server":"http://h","id":1,"username":"b"}', '{"id":"a","username":"b"}', '']) {
        final t = setup();
        t.store.data[AuthSession.storageKey] = raw;
        expect(await t.session.restore(), isFalse, reason: raw);
        expect(t.server.requests, isEmpty, reason: raw);
      }
    });
  });

  group('logout', () {
    test('signs out at once, revokes on the server and forgets the note', () async {
      final t = setup();
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      await t.session.logout();
      expect(t.session.status, AuthStatus.out);
      expect(t.session.endedByServer, isFalse);
      expect(t.server.requests.last, 'POST /auth/logout/');
      expect(await t.session.remembered, isFalse);
    });

    test('works with the server unreachable', () async {
      final t = setup();
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      t.server.overrides['/auth/logout/'] = (_) => throw Exception('offline');
      await t.session.logout();
      expect(t.session.status, AuthStatus.out);
      await t.session.logout(); // a second tap changes nothing
    });
  });

  group('renewal', () {
    test('the token is renewed on its own, and a refusal ends the session by the server', () async {
      final t = setup(expiresIn: 1, minRenew: Duration.zero);
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(t.server.refreshes, greaterThanOrEqualTo(1));
      expect(t.session.status, AuthStatus.signedIn);

      t.server.cookieValid = false;
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(t.session.status, AuthStatus.out);
      expect(t.session.endedByServer, isTrue);
    });

    test('a renewal that fails without a refusal keeps the session and tries again', () async {
      final t = setup(expiresIn: 1, minRenew: Duration.zero);
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      t.server.overrides['/auth/refresh/'] = (_) => throw Exception('wifi dropped');
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(t.session.status, AuthStatus.signedIn);
      t.server.overrides.clear();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(t.server.refreshes, greaterThanOrEqualTo(1));
    });
  });

  group('call', () {
    test('without a session it refuses at once', () async {
      final t = setup();
      await expectLater(t.session.call((_) async => 1), throwsA(isA<AuthApiError>().having((e) => e.code, 'code', 'not_signed_in')));
    });

    test('a 401 renews the token once and runs again; a second 401 is the caller\'s', () async {
      final t = setup();
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      final tokens = <String>[];
      final result = await t.session.call((token) async {
        tokens.add(token);
        if (tokens.length == 1) throw const AuthApiError(401, 'unauthorized');
        return 'ok';
      });
      expect(result, 'ok');
      expect(tokens.toSet().length, 2, reason: 'the second try carries the new token');

      await expectLater(t.session.call((_) async => throw const AuthApiError(401, 'unauthorized')), throwsA(isA<AuthApiError>()));
      // other errors pass straight through, with no renewal
      final before = t.server.refreshes;
      await expectLater(t.session.call((_) async => throw const AuthApiError(500, 'internal_error')), throwsA(isA<AuthApiError>()));
      expect(t.server.refreshes, before);
    });

    test('many calls refused together share one renewal', () async {
      final t = setup();
      await t.session.login(home, 'ana@casa.local', 'senha1234', keepSignedIn: true);
      final before = t.server.refreshes;
      final stale = await t.session.call((token) async => token);
      await Future.wait([
        for (var i = 0; i < 6; i++)
          t.session.call((token) async {
            if (token == stale) throw const AuthApiError(401, 'expired');
            return token;
          }),
      ]);
      expect(t.server.refreshes - before, 1);
    });
  });
}
