import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/features/auth/data/auth_session.dart';
import 'package:mobile/features/auth/data/server_trust.dart';
import 'package:mobile/features/auth/presentation/pages/start_gate.dart';
import 'package:mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/providers/notes_provider.dart';
import 'package:mobile/core/api/auth_api.dart';
import 'package:mobile/core/network/pairing.dart';

import '../../support/choose_first.dart';
import '../../support/discovery_fakes.dart';
import '../../support/fake_auth_server.dart';

class Rig {
  Rig(this.server, this.store, this.session);
  final FakeAuthServer server;
  final MemoryKeyValueStore store;
  final AuthSession session;
}

/// The login screen over a fake backend. [choose] false leaves no server chosen.
Future<Rig> pumpLogin(WidgetTester tester, {bool choose = true, bool signedIn = false, double width = 450}) async {
  final server = FakeAuthServer()..accounts['ana@casa.local'] = (id: 'id-1', username: 'ana', password: 'senha1234');
  final store = MemoryKeyValueStore();
  final session = AuthSession(store: store, apiFactory: server.factory);
  final discovery = FakeDiscovery(sampleServers);
  final trust = ServerTrust(MemoryKeyValueStore());
  for (final s in discovery.current) {
    await trust.remember(s.name, s.id);
  }
  final workspaces = <Workspace>[];
  tester.view.physicalSize = Size(width * 2, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        authSessionProvider.overrideWithValue(session),
        serverTrustProvider.overrideWithValue(trust),
        pairedStoreProvider.overrideWithValue(MemoryPairedStore()),
        serverDiscoveryProvider.overrideWithValue(discovery),
        serverProbeProvider.overrideWithValue((_) async => true),
        accountWorkspaceProvider.overrideWith((ref, id) async {
          final ws = Workspace(NotesDb.inMemory());
          workspaces.add(ws);
          return ws;
        }),
        workspaceProvider.overrideWith((ref) async => Workspace(NotesDb.inMemory())),
      ],
      child: PindrelApp(home: const StartGate()),
    ),
  );
  await tester.pump();
  if (choose) await chooseFirst(tester);
  final rig = Rig(server, store, session);
  _rigs.add(rig);
  return rig;
}

Future<void> fill(WidgetTester tester, {String email = 'ana@casa.local', String? username, String password = 'senha1234'}) async {
  await tester.enterText(find.byKey(const Key('email-field')), email);
  if (username != null) await tester.enterText(find.byKey(const Key('username-field')), username);
  await tester.enterText(find.byKey(const Key('password-field')), password);
}

/// Lets the fake server's answers (and what the screens do with them) run to the end: they take several turns of the
/// real event loop, which `pumpAndSettle` alone does not wait for.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, label));
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pump();
  await settle(tester);
}

final _rigs = <Rig>[];

/// A widget test that closes the screen and the sessions' renewal timers before it ends (a pending timer fails it).
void loginTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
  await body(tester);
  await tester.pumpWidget(const SizedBox());
  for (final rig in _rigs) {
    rig.session.dispose();
  }
  _rigs.clear();
});

/// The account chip of the notes screen, by the name it shows.
Finder accountMenu(String name) => find.byWidgetPredicate((w) => w is PopupMenuButton && w.tooltip == 'Menu da conta de $name');

String errorText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('form-error'))).data!;

void main() {
  loginTest('sign in opens the account\'s notes with the person\'s name, and the session is the server\'s', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester);
    await submit(tester, 'Entrar');

    expect(rig.session.status, AuthStatus.signedIn);
    expect(find.text('Nenhuma página ainda'), findsOneWidget);
    expect(find.byKey(const Key('form-error')), findsNothing);
    expect(find.text('Bem-vindo de volta'), findsNothing, reason: 'the login is gone from the stack');
    await tester.pageBack().catchError((_) {});
    expect(find.text('Bem-vindo de volta'), findsNothing);
  });

  loginTest('the account menu has "Conta" (who is in) and "Sair da conta" one tap away, which goes back to the login', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester);
    await submit(tester, 'Entrar');

    await tester.tap(accountMenu('ana'));
    await tester.pumpAndSettle();
    expect(find.text('Conta e servidor'), findsNothing, reason: 'signed in, the entry is just "Conta"');
    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    expect(find.text('ana@casa.local'), findsOneWidget);
    expect(find.text('Sair da conta'), findsNothing, reason: 'leaving is in the menu, not on the account screen');
    await tester.tapAt(const Offset(5, 5)); // closes the dialog
    await tester.pumpAndSettle();

    await tester.tap(accountMenu('ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair da conta'));
    await tester.pump();
    await settle(tester);

    expect(rig.session.status, AuthStatus.out);
    expect(rig.server.requests.last, 'POST /auth/logout/');
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.text('Sua sessão terminou. Entre de novo.'), findsNothing, reason: 'a deliberate sign-out is not "the session ended"');
  });

  loginTest('"Sair da conta" leaves at once even when the server is slow to answer the logout', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester);
    await submit(tester, 'Entrar');

    await tester.tap(accountMenu('ana'));
    await tester.pumpAndSettle();
    rig.server.gate = Completer<void>(); // from now on the server holds every answer
    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();

    expect(rig.session.status, AuthStatus.out);
    expect(find.text('Bem-vindo de volta'), findsOneWidget, reason: 'the person must not wait for the server to be signed out');
    rig.server.gate!.complete();
    await settle(tester);
  });

  loginTest('a wrong password says so in Portuguese, keeps what was typed and lets the person try again', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester, password: 'errada');
    await submit(tester, 'Entrar');
    expect(errorText(tester), 'E-mail ou senha incorretos.');
    expect(rig.session.status, AuthStatus.out);
    expect(find.text('ana@casa.local'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('password-field')), 'senha1234');
    await submit(tester, 'Entrar');
    expect(rig.session.status, AuthStatus.signedIn);
  });

  loginTest('nothing is sent when the fields are wrong, and the first wrong field is named', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester, email: 'sem-arroba', password: '');
    await submit(tester, 'Entrar');
    expect(errorText(tester), 'Informe um e-mail válido.');
    await tester.enterText(find.byKey(const Key('email-field')), 'ana@casa.local');
    await submit(tester, 'Entrar');
    expect(errorText(tester), 'Digite a senha.');
    expect(rig.server.requests, isEmpty);
  });

  loginTest('no server chosen: it says so instead of failing silently, and sends nothing', (tester) async {
    final rig = await pumpLogin(tester, choose: false);
    await fill(tester);
    await submit(tester, 'Entrar');
    expect(errorText(tester), 'Escolha um servidor para entrar.');
    expect(rig.server.requests, isEmpty);
  });

  loginTest('a server that does not answer, a busy one and a broken one each have their own message', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester);

    rig.server.overrides['/auth/login/'] = (_) => throw Exception('no route to host');
    await submit(tester, 'Entrar');
    expect(errorText(tester), contains('conexão'));

    rig.server.overrides['/auth/login/'] = (r) => throw TimeoutException('slow');
    await submit(tester, 'Entrar');
    expect(errorText(tester), contains('demorou'));

    rig.server.overrides['/auth/login/'] = (_) => throw const FormatException();
    await submit(tester, 'Entrar');
    expect(errorText(tester), contains('conexão'));
    expect(tester.takeException(), isNull);
  });

  loginTest('while the request runs the button is locked and says what is happening; taps do not repeat it', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester);
    rig.server.gate = Completer();
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();
    expect(find.text('Entrando…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextField>(find.byKey(const Key('email-field'))).enabled, isFalse);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();

    rig.server.gate!.complete();
    await tester.pumpAndSettle();
    expect(rig.server.requests.where((r) => r == 'POST /auth/login/'), hasLength(1));
  });

  loginTest('sign-up creates the account, signs in with the same data and opens it', (tester) async {
    final rig = await pumpLogin(tester);
    await tester.tap(find.text('Criar conta').last);
    await tester.pumpAndSettle();
    await fill(tester, email: 'bia@casa.local', username: 'bia', password: 'outrasenha1');
    await submit(tester, 'Criar conta');

    expect(rig.server.requests, ['POST /auth/register/', 'POST /auth/login/', 'GET /auth/me/']);
    expect(rig.session.user!.username, 'bia');
    expect(find.text('Nenhuma página ainda'), findsOneWidget);
  });

  loginTest('sign-up: an e-mail already taken is explained, nothing is signed in', (tester) async {
    final rig = await pumpLogin(tester);
    await tester.tap(find.text('Criar conta').last);
    await tester.pumpAndSettle();
    await fill(tester, username: 'ana2', password: 'outrasenha1');
    await submit(tester, 'Criar conta');
    expect(errorText(tester), contains('já está cadastrado'));
    expect(rig.session.status, AuthStatus.out);
  });

  loginTest('sign-up where registration is off: the link gives way to a sentence and the form goes back to sign-in', (tester) async {
    final rig = await pumpLogin(tester);
    rig.server.registrationOpen = false;
    await tester.tap(find.text('Criar conta').last);
    await tester.pumpAndSettle();
    await fill(tester, email: 'bia@casa.local', username: 'bia', password: 'outrasenha1');
    await submit(tester, 'Criar conta');
    expect(find.byKey(const Key('registration-closed')), findsOneWidget);
    expect(find.byKey(const ValueKey('toggle-mode')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });

  loginTest('sign-up: the account was created but the sign-in after it failed: tells the person to sign in', (tester) async {
    final rig = await pumpLogin(tester);
    rig.server.overrides['/auth/login/'] = (_) => throw Exception('dropped');
    await tester.tap(find.text('Criar conta').last);
    await tester.pumpAndSettle();
    await fill(tester, email: 'bia@casa.local', username: 'bia', password: 'outrasenha1');
    await submit(tester, 'Criar conta');
    expect(find.byKey(const Key('form-notice')), findsOneWidget);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(rig.server.accounts, contains('bia@casa.local'));
  });

  loginTest('a person leaving the screen while the request runs does not crash it', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester);
    rig.server.gate = Completer();
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    rig.server.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  loginTest('a hostile e-mail and a huge password: no overflow, no crash', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester, email: '<script>alert(1)</script>@x.y', password: '🚀' * 30);
    await submit(tester, 'Entrar');
    expect(errorText(tester), isNotEmpty);
    expect(rig.session.status, AuthStatus.out);
    expect(tester.takeException(), isNull);
  });

  loginTest('on start, a device that stayed signed in goes straight to its account; otherwise to the notes of the device', (tester) async {
    final first = await pumpLogin(tester);
    await fill(tester);
    await submit(tester, 'Entrar');
    final note = first.store.data[AuthSession.storageKey]!;

    // "restart the app": a new session over the same store
    final server = first.server;
    final store = MemoryKeyValueStore()..data[AuthSession.storageKey] = note;
    final session = AuthSession(store: store, apiFactory: server.factory);
    _rigs.add(Rig(server, store, session));
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          authSessionProvider.overrideWithValue(session),
          accountWorkspaceProvider.overrideWith((ref, id) async => Workspace(NotesDb.inMemory())),
          workspaceProvider.overrideWith((ref) async => Workspace(NotesDb.inMemory())),
        ],
        child: const PindrelApp(),
      ),
    );
    await settle(tester);
    expect(accountMenu('ana'), findsOneWidget);
  });

  loginTest('after a restart that restored the session, "Sair da conta" really signs out (the login comes back, not the account)', (tester) async {
    final first = await pumpLogin(tester);
    await fill(tester);
    await submit(tester, 'Entrar');
    final note = first.store.data[AuthSession.storageKey]!;

    final server = first.server;
    final store = MemoryKeyValueStore()..data[AuthSession.storageKey] = note;
    final session = AuthSession(store: store, apiFactory: server.factory);
    _rigs.add(Rig(server, store, session));
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          authSessionProvider.overrideWithValue(session),
          accountWorkspaceProvider.overrideWith((ref, id) async => Workspace(NotesDb.inMemory())),
          workspaceProvider.overrideWith((ref) async => Workspace(NotesDb.inMemory())),
        ],
        child: const PindrelApp(),
      ),
    );
    await settle(tester);
    expect(accountMenu('ana'), findsOneWidget);

    await tester.tap(accountMenu('ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair da conta'));
    await tester.pump();
    await settle(tester);

    expect(session.status, AuthStatus.out);
    expect(find.text('Bem-vindo de volta'), findsOneWidget, reason: 'the cached restore must not bring the account back');
    expect(accountMenu('ana'), findsNothing);
    expect(store.data[AuthSession.storageKey] ?? '', isEmpty, reason: 'the kept session is forgotten');
  });

  loginTest('a session the server ends while the account is open sends the person back with a note', (tester) async {
    final rig = await pumpLogin(tester);
    await fill(tester);
    await submit(tester, 'Entrar');
    // a request is refused (401), the renewal is refused too: the server has ended the session
    rig.server.cookieValid = false;
    await tester.runAsync(() => rig.session.call<void>((_) async => throw const AuthApiError(401, 'unauthorized')).catchError((_) {}));
    await settle(tester);
    expect(rig.session.status, AuthStatus.out);
    expect(find.text('Sua sessão terminou. Entre de novo.'), findsOneWidget);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
  });

  loginTest('the app starts on the login, and "Continuar offline" opens the notes of the device', (tester) async {
    await pumpLogin(tester, choose: false);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.text('Nenhuma página ainda'), findsNothing);
    await tester.ensureVisible(find.text('Continuar offline neste dispositivo'));
    await tester.tap(find.text('Continuar offline neste dispositivo'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma página ainda'), findsOneWidget);
    expect(accountMenu('Você'), findsOneWidget);
  });
}
