import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/pairing.dart';
import 'package:mobile/core/network/server_security.dart';
import 'package:mobile/features/auth/data/pairing_flow.dart';

import '../../support/pairing_fakes.dart';

PairingFlow flow(FakePairer p, {FlowMode mode = FlowMode.compare, String room = '4821', Uri? base, TlsOffer? offer = const TlsOffer(port: 8443, serverId: 'abc123')}) {
  return PairingFlow(
    base: base ?? Uri.parse('http://192.168.1.5:8086'),
    mode: mode,
    room: room,
    store: MemoryPairedStore(),
    pairer: p.call,
    offerFor: (_) async => offer,
    confirmTimeout: const Duration(milliseconds: 80),
  );
}

Future<void> until(PairingFlow f, FlowPhase phase) async {
  for (var i = 0; i < 200 && f.state.phase != phase; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(f.state.phase, phase);
}

void main() {
  test('comparar: os números aparecem, a pessoa confirma e o servidor fica pareado com o id que anunciou', () async {
    final p = FakePairer(['123456']);
    final f = flow(p, mode: FlowMode.compare)..start();
    await until(f, FlowPhase.showing);
    expect(f.state.prompt!.digits, '123456');
    expect(f.state.tlsPort, 8443);
    f.confirmSame();
    await until(f, FlowPhase.paired);
    expect(f.state.paired!.serverId, 'abc123');
    expect(f.state.paired!.hostPort, '192.168.1.5:8443');
  });

  test('os números expiram e vêm outros: cada conjunto vale uma vez só', () async {
    final p = FakePairer(['111111', '222222', '333333']);
    final f = flow(p)..start();
    await until(f, FlowPhase.showing);
    final first = f.state.prompt!.digits;
    expect(f.state.round, 1);
    // nobody answers: after the timeout the digits are replaced by a new session
    for (var i = 0; i < 200 && f.state.round < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await until(f, FlowPhase.showing);
    expect(f.state.round, greaterThanOrEqualTo(2));
    expect(f.state.prompt!.digits, isNot(first), reason: 'the old digits are never shown again');
    f.confirmSame();
    await until(f, FlowPhase.paired);
    expect(p.shown.toSet().length, p.shown.length, reason: 'no set of digits was reused: ${p.shown}');
  });

  test('uma tela esquecida não pede números para sempre', () async {
    final p = FakePairer(List.generate(20, (i) => '${100000 + i}'));
    final f = PairingFlow(
      base: Uri.parse('http://192.168.1.5:8086'),
      mode: FlowMode.compare,
      room: '4821',
      store: MemoryPairedStore(),
      pairer: p.call,
      offerFor: (_) async => const TlsOffer(port: 8443),
      confirmTimeout: const Duration(milliseconds: 10),
      maxRounds: 4,
    )..start();
    await until(f, FlowPhase.failed);
    expect(f.state.failure, PairingFailure.expired);
    expect(p.calls, 4);
  });

  test('dizer que são diferentes encerra sem guardar nada', () async {
    final p = FakePairer(['123456']);
    final f = flow(p)..start();
    await until(f, FlowPhase.showing);
    f.reject();
    await until(f, FlowPhase.failed);
    expect(f.state.failure, PairingFailure.declined);
    expect(f.state.paired, isNull);
  });

  test('digitar: o código é obrigatório, erros são contados e três erros derrubam a sessão', () async {
    final p = FakePairer(['123456']);
    final f = flow(p, mode: FlowMode.type)..start();
    await until(f, FlowPhase.showing);
    f.confirmSame(); // in this mode the person cannot skip the typing
    expect(f.state.phase, FlowPhase.showing);
    expect(f.submit(''), isFalse);
    expect(f.state.wrongTries, 1);
    expect(f.submit('12345'), isFalse);
    expect(f.state.wrongTries, 2);
    expect(f.state.phase, FlowPhase.showing);
    expect(f.submit('000000'), isFalse);
    await until(f, FlowPhase.failed);
    expect(f.state.failure, PairingFailure.declined);
  });

  test('digitar: aceita espaços no meio e o número certo pareia', () async {
    final p = FakePairer(['123456']);
    final f = flow(p, mode: FlowMode.type)..start();
    await until(f, FlowPhase.showing);
    expect(f.submit('abc'), isFalse);
    expect(f.submit(' 123 456 '), isTrue);
    await until(f, FlowPhase.paired);
  });

  test('digitar: um conjunto novo zera os erros e só vale o número do conjunto atual', () async {
    final p = FakePairer(['111111', '222222']);
    final f = flow(p, mode: FlowMode.type)..start();
    await until(f, FlowPhase.showing);
    f.submit('999999');
    expect(f.state.wrongTries, 1);
    for (var i = 0; i < 200 && f.state.round < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await until(f, FlowPhase.showing);
    expect(f.state.wrongTries, 0);
    expect(f.submit('111111'), isFalse, reason: 'the digits of the expired session are worthless');
    expect(f.submit('222222'), isTrue);
    await until(f, FlowPhase.paired);
  });

  test('comparar: digitar não faz nada, e fora da hora de mostrar também não', () async {
    final p = FakePairer(['123456']);
    final f = flow(p)..start();
    expect(f.submit('123456'), isFalse);
    await until(f, FlowPhase.showing);
    expect(f.submit('123456'), isFalse);
    f.confirmSame();
    await until(f, FlowPhase.paired);
    f.confirmSame(); // twice, or late: nothing breaks
    f.reject();
    expect(f.state.phase, FlowPhase.paired);
  });

  test('servidor sem HTTPS: avisa e não tenta parear', () async {
    final p = FakePairer(['123456']);
    final f = flow(p, offer: null)..start();
    await until(f, FlowPhase.noTls);
    expect(p.calls, 0);
  });

  test('endereço https explícito dispensa perguntar a porta', () async {
    final p = FakePairer(['123456']);
    var asked = false;
    final f = PairingFlow(
      base: Uri.parse('https://192.168.1.5:9443'),
      mode: FlowMode.compare,
      room: '4821',
      store: MemoryPairedStore(),
      pairer: p.call,
      offerFor: (_) async {
        asked = true;
        return null;
      },
    )..start();
    await until(f, FlowPhase.showing);
    expect(asked, isFalse);
    expect(f.state.tlsPort, 9443);
    f.cancel();
  });

  test('falhas do servidor (ocupado, bloqueado, mudo) chegam à tela e não pareiam', () async {
    for (final reason in [PairingFailure.busy, PairingFailure.locked, PairingFailure.unreachable, PairingFailure.protocol, PairingFailure.notACertificate]) {
      final f = flow(FakePairer(['123456'], result: PairingFailed(reason)))..start();
      await until(f, FlowPhase.failed);
      expect(f.state.failure, reason);
    }
  });

  test('fechar a tela cancela, solta o que espera e nada muda depois', () async {
    final p = FakePairer(['123456']);
    final f = flow(p)..start();
    await until(f, FlowPhase.showing);
    f.cancel();
    expect(f.state.phase, FlowPhase.cancelled);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(f.state.phase, FlowPhase.cancelled);
    expect(f.state.paired, isNull);
    f.cancel(); // twice
    f.dispose();
  });

  test('fechar antes de o servidor responder sobre o HTTPS também é seguro', () async {
    final slow = Completer<TlsOffer?>();
    final p = FakePairer(['123456']);
    final f = PairingFlow(
      base: Uri.parse('http://192.168.1.5:8086'),
      mode: FlowMode.compare,
      room: '4821',
      store: MemoryPairedStore(),
      pairer: p.call,
      offerFor: (_) => slow.future,
    )..start();
    f.cancel();
    slow.complete(const TlsOffer(port: 8443));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(p.calls, 0);
    expect(f.state.phase, FlowPhase.cancelled);
  });

  test('chamar start duas vezes abre uma sessão só', () async {
    final p = FakePairer(['123456']);
    final f = flow(p);
    unawaited(f.start());
    unawaited(f.start());
    await until(f, FlowPhase.showing);
    expect(p.calls, 1);
    f.cancel();
  });

  test('uma sala que o servidor não conhece encerra o fluxo dizendo isso, sem números e sem parear', () async {
    final p = FakePairer(['123456']);
    final f = flow(p, room: '0000')..start();
    await until(f, FlowPhase.failed);
    expect(f.state.failure, PairingFailure.badRoom);
    expect(f.state.prompt, isNull);
    expect(p.rooms, ['0000']);
  });

  test('a mesma sala vale para todas as renovações dos números', () async {
    final p = FakePairer(['111111', '222222']);
    final f = flow(p, room: '4821')..start();
    await until(f, FlowPhase.showing);
    for (var i = 0; i < 200 && f.state.round < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await until(f, FlowPhase.showing);
    expect(p.rooms.toSet(), {'4821'}, reason: 'the room is the same, the digits are new');
    f.cancel();
  });

  group('código mestre', () {
    PairingFlow master(FakeMasterPairer m, {String code = '0410-6105-0R3G-G28A', TlsOffer? offer = const TlsOffer(port: 8443, serverId: 'abc')}) => PairingFlow(
          base: Uri.parse('http://192.168.1.5:8086'),
          mode: FlowMode.master,
          master: code,
          store: MemoryPairedStore(),
          pairer: FakePairer(['123456']).call,
          masterPairer: m.call,
          offerFor: (_) async => offer,
        );

    test('o código certo pareia sem nenhum número para comparar', () async {
      final m = FakeMasterPairer();
      final f = master(m)..start();
      await until(f, FlowPhase.paired);
      expect(f.state.prompt, isNull);
      expect(f.state.paired!.serverId, 'abc');
      expect(f.state.paired!.hostPort, '192.168.1.5:8443');
      expect(m.tried, ['0410-6105-0R3G-G28A']);
    });

    test('o código errado é dito como recusado e nada é guardado', () async {
      final f = master(FakeMasterPairer(), code: 'ZZZZ-ZZZZ-ZZZZ-ZZZZ')..start();
      await until(f, FlowPhase.failed);
      expect(f.state.failure, PairingFailure.badCode);
      expect(f.state.paired, isNull);
    });

    test('digitar ou "são iguais" não fazem nada neste modo', () async {
      final f = master(FakeMasterPairer(result: const PairingFailed(PairingFailure.locked)))..start();
      expect(f.submit('123456'), isFalse);
      f.confirmSame();
      await until(f, FlowPhase.failed);
      expect(f.state.failure, PairingFailure.locked);
    });

    test('servidor sem HTTPS: avisa e não tenta nada', () async {
      final m = FakeMasterPairer();
      final f = master(m, offer: null)..start();
      await until(f, FlowPhase.noTls);
      expect(m.tried, isEmpty);
    });

    test('fechar a tela no meio solta tudo', () async {
      final m = FakeMasterPairer();
      final f = master(m)..start();
      f.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(f.state.phase, FlowPhase.cancelled);
    });
  });
}
