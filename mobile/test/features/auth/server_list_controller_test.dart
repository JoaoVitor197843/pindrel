import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/server_discovery.dart';
import 'package:mobile/core/network/pairing.dart';
import 'package:mobile/features/auth/data/server_list_controller.dart';
import 'package:mobile/features/auth/data/server_list_state.dart';
import 'package:mobile/features/auth/data/server_option.dart';
import 'package:mobile/features/auth/data/server_trust.dart';

import '../../support/discovery_fakes.dart';

/// A discovery that can also fail.
class ErrorDiscovery implements ServerDiscovery {
  final controller = StreamController<List<DiscoveredServer>>();

  @override
  Stream<List<DiscoveredServer>> watch() => controller.stream;
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

ServerOption option(String name, {String ip = '10.0.0.1'}) =>
    ServerOption.fromDiscovered(server(name, addresses: [ip]));

/// The person of these tests: taps the first server that shows up (the app itself chooses nothing).
void pickFirst(ServerListController c) {
  final sub = c.stream.listen((s) {
    if (s.selected == null && s.connecting == null && s.pendingChange == null && s.available.isNotEmpty) {
      unawaited(c.select(s.available.first));
    }
  });
  addTearDown(sub.cancel);
}

void main() {
  late FakeDiscovery discovery;
  late ServerListController controller;

  ServerListController make({List<DiscoveredServer>? initial, bool tap = true}) {
    discovery = FakeDiscovery(initial ?? sampleServers);
    controller = ServerListController(discovery: discovery);
    if (tap) pickFirst(controller);
    addTearDown(controller.dispose);
    return controller;
  }

  group('estado inicial', () {
    test('antes de qualquer resposta: vazio, sem escolha', () {
      final c = ServerListController(discovery: FakeDiscovery());
      addTearDown(c.dispose);
      expect(c.current.available, isEmpty);
      expect(c.current.selected, isNull);
      expect(c.current.connection, ServerConnection.none);
      expect(c.current.disconnected, isEmpty);
    });

    test('sem servidores achados: continua sem escolha', () async {
      make(initial: const []);
      await flush();
      expect(controller.current.connection, ServerConnection.none);
    });

    test('nada é escolhido sozinho: a lista chega e a escolha espera a pessoa', () async {
      make(tap: false);
      await flush();
      expect(controller.current.available, hasLength(3));
      expect(controller.current.selected, isNull);
      expect(controller.current.connection, ServerConnection.none);
    });

    test('a lista chega ordenada como a descoberta a entrega', () async {
      make();
      await flush();
      expect(controller.current.available.map((s) => s.name), [
        'Casa',
        'Escritório',
        'Nuvem',
      ]);
    });
  });

  group('stream', () {
    test('aceita vários ouvintes e cada um recebe cada mudança', () async {
      make();
      final a = <ServerListState>[];
      final b = <ServerListState>[];
      final subA = controller.stream.listen(a.add);
      final subB = controller.stream.listen(b.add);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);

      discovery.emit([
        server('Aaa', addresses: ['10.0.0.1']),
      ]);
      await flush();
      expect(a.length, b.length);
      expect(a.last.available.map((s) => s.name), ['Aaa']);
    });

    test('current acompanha o último estado emitido', () async {
      make();
      final seen = <ServerListState>[];
      final sub = controller.stream.listen(seen.add);
      addTearDown(sub.cancel);
      discovery.emit(sampleServers.sublist(1));
      await flush();
      expect(identical(controller.current, seen.last), isTrue);
    });

    test('assina a descoberta uma vez só e cancela ao descartar', () async {
      make();
      await flush();
      controller.stream.listen((_) {}).cancel();
      controller.stream.listen((_) {}).cancel();
      expect(discovery.listeners, 1);
      await controller.dispose();
      expect(discovery.listeners, 0);
    });

    test('descartar fecha o stream', () async {
      make();
      final done = controller.stream.toList();
      await controller.dispose();
      expect(await done, isA<List<ServerListState>>());
    });
  });

  group('escolha', () {
    test('o usuário escolhe, e a escolha dura entre as atualizações', () async {
      make();
      await flush();
      final nuvem = controller.current.available.last;
      controller.select(nuvem);
      expect(controller.current.selected, nuvem);

      discovery.emit(sampleServers.reversed.toList());
      await flush();
      expect(controller.current.selected?.name, 'Nuvem');
      expect(controller.current.connection, ServerConnection.connected);
    });

    test('novos servidores não mudam a escolha já feita', () async {
      make();
      await flush();
      expect(controller.current.selected?.name, 'Casa');
      discovery.emit([
        server('Aaa', addresses: ['10.0.0.1']),
        ...sampleServers,
      ]);
      await flush();
      expect(controller.current.selected?.name, 'Casa');
    });

    test(
      'um servidor que muda de endereço segue escolhido, com o endereço novo',
      () async {
        make(
          initial: [
            server('Casa', addresses: ['10.0.0.1']),
          ],
        );
        await flush();
        expect(controller.current.selected?.address, '10.0.0.1:8080');

        discovery.emit([
          server('Casa', addresses: ['10.0.0.77']),
        ]);
        await flush();
        expect(controller.current.selected?.address, '10.0.0.77:8080');
        expect(
          controller.current.selected?.baseUri,
          Uri.parse('http://10.0.0.77:8080'),
        );
      },
    );
  });

  group('o escolhido sai da rede', () {
    test(
      'continua escolhido, mas passa a desconectado e vai para a lista de desconectados',
      () async {
        make();
        await flush();
        final casa = controller.current.selected!;
        expect(casa.name, 'Casa');

        discovery.emit(sampleServers.sublist(1));
        await flush();
        final s = controller.current;
        expect(s.selected, casa);
        expect(s.connection, ServerConnection.disconnected);
        expect(s.available.map((o) => o.name), ['Escritório', 'Nuvem']);
        expect(s.disconnected, [casa]);
      },
    );

    test(
      'não troca por outro servidor sozinho, nem quando há outros disponíveis',
      () async {
        make();
        await flush();
        discovery.emit(sampleServers.sublist(1));
        await flush();
        expect(controller.current.selected?.name, 'Casa');
        discovery.emit([
          ...sampleServers.sublist(1),
          server('Novo', addresses: ['10.0.0.5']),
        ]);
        await flush();
        expect(controller.current.selected?.name, 'Casa');
      },
    );

    test(
      'se tudo some, o escolhido fica desconectado (não volta a "sem escolha")',
      () async {
        make();
        await flush();
        discovery.emit([]);
        await flush();
        expect(controller.current.available, isEmpty);
        expect(controller.current.selected?.name, 'Casa');
        expect(controller.current.connection, ServerConnection.disconnected);
      },
    );

    test('quando volta, volta a conectado e sai dos desconectados', () async {
      make();
      await flush();
      discovery.emit(sampleServers.sublist(1));
      await flush();
      expect(controller.current.disconnected, isNotEmpty);

      discovery.emit(sampleServers);
      await flush();
      expect(controller.current.connection, ServerConnection.connected);
      expect(controller.current.disconnected, isEmpty);
    });

    test('volta com outro endereço: conectado com o endereço novo', () async {
      make(
        initial: [
          server('Casa', addresses: ['10.0.0.1']),
        ],
      );
      await flush();
      discovery.emit([]);
      await flush();
      discovery.emit([
        server('Casa', addresses: ['10.0.0.9']),
      ]);
      await flush();
      expect(controller.current.connection, ServerConnection.connected);
      expect(controller.current.selected?.address, '10.0.0.9:8080');
    });

    test('escolher outro servidor larga o desconectado', () async {
      make();
      await flush();
      discovery.emit(sampleServers.sublist(1));
      await flush();
      controller.select(controller.current.available.first);
      expect(controller.current.selected?.name, 'Escritório');
      expect(controller.current.connection, ServerConnection.connected);
      expect(controller.current.disconnected, isEmpty);
    });

    test('escolher de novo o próprio desconectado não muda nada', () async {
      make();
      await flush();
      discovery.emit(sampleServers.sublist(1));
      await flush();
      final casa = controller.current.selected!;
      controller.select(casa);
      expect(controller.current.selected, casa);
      expect(controller.current.connection, ServerConnection.disconnected);
    });

    test(
      'um servidor que NÃO era o escolhido some sem deixar rastro',
      () async {
        make();
        await flush();
        discovery.emit([
          sampleServers[0],
          sampleServers[2],
        ]); // Escritório leaves
        await flush();
        expect(controller.current.available.map((o) => o.name), [
          'Casa',
          'Nuvem',
        ]);
        expect(controller.current.disconnected, isEmpty);
        expect(controller.current.connection, ServerConnection.connected);
      },
    );
  });

  group('erros da busca', () {
    test('o erro fica no estado e a lista anterior é mantida', () async {
      final d = ErrorDiscovery();
      final c = ServerListController(discovery: d);
      pickFirst(c);
      addTearDown(c.dispose);
      d.controller.add(sampleServers);
      await flush();
      d.controller.addError(StateError('sem permissão'));
      await flush();
      expect(c.current.searchError, isA<StateError>());
      expect(c.current.available, hasLength(3));
      expect(c.current.selected?.name, 'Casa');
    });

    test('o erro some quando a busca volta a responder', () async {
      final d = ErrorDiscovery();
      final c = ServerListController(discovery: d);
      pickFirst(c);
      addTearDown(c.dispose);
      d.controller.addError(StateError('x'));
      await flush();
      expect(c.current.searchError, isNotNull);
      d.controller.add(sampleServers);
      await flush();
      expect(c.current.searchError, isNull);
    });
  });

  group('teste de conexão ao escolher', () {
    ServerListController makeProbed(Future<bool> Function(Uri) probe, {bool tap = true}) {
      discovery = FakeDiscovery(sampleServers);
      controller = ServerListController(
        discovery: discovery,
        probe: probe,
      );
      if (tap) pickFirst(controller);
      addTearDown(controller.dispose);
      return controller;
    }

    test('responde: escolhe, e connecting aparece enquanto espera', () async {
      final gate = Completer<bool>();
      Uri? asked;
      makeProbed((uri) {
        asked = uri;
        return gate.future;
      }, tap: false);
      await flush();
      final other = controller.current.available.last;
      final result = controller.select(other);
      expect(controller.current.connecting, other);
      expect(controller.current.selected, isNot(other));
      gate.complete(true);
      expect(await result, isTrue);
      expect(asked, other.baseUri);
      expect(controller.current.connecting, isNull);
      expect(controller.current.selected, other);
    });

    test('não responde: a escolha anterior fica', () async {
      var first = true;
      makeProbed((_) async {
        final ok = first; // the first call is the pick made at start
        first = false;
        return ok;
      });
      await flush();
      final before = controller.current.selected;
      expect(
        await controller.select(controller.current.available.last),
        isFalse,
      );
      expect(controller.current.selected, before);
      expect(controller.current.connecting, isNull);
    });

    test('a consulta que lança conta como falha', () async {
      var first = true;
      makeProbed((_) async {
        if (first) {
          first = false;
          return true;
        }
        throw StateError('boom');
      });
      await flush();
      expect(
        await controller.select(controller.current.available.last),
        isFalse,
      );
      expect(controller.current.connecting, isNull);
    });

    test(
      'toques repetidos enquanto conecta não disparam outra consulta',
      () async {
        final gate = Completer<bool>();
        var calls = 0;
        makeProbed((_) {
          calls++;
          return calls == 1 ? Future.value(true) : gate.future;
        });
        await flush();
        final other = controller.current.available.last;
        final first = controller.select(other);
        expect(await controller.select(other), isFalse);
        gate.complete(true);
        await first;
        expect(calls, 2, reason: 'the pick at start plus one for the tap');
      },
    );

    test('o já escolhido não é testado de novo', () async {
      var calls = 0;
      makeProbed((_) async {
        calls++;
        return true;
      });
      await flush();
      expect(calls, 1, reason: 'the pick at start is tested');
      expect(await controller.select(controller.current.selected!), isTrue);
      expect(calls, 1);
    });
  });

  group('identidade do servidor', () {
    late ServerTrust trust;
    late List<Uri> probed;
    late List<Uri> autoProbed;

    Future<ServerListController> makeTrusted(
      List<DiscoveredServer> initial, {
      int random = 0,
      bool probeOk = true,
    }) async {
      trust = ServerTrust(MemoryKeyValueStore());
      probed = [];
      var answer =
          true; // the pick at start must succeed; [probeOk] is for what follows
      discovery = FakeDiscovery(initial);
      controller = ServerListController(
        discovery: discovery,
        trust: trust,
        probe: (uri) async {
          probed.add(uri);
          return answer;
        },
      );
      pickFirst(controller);
      addTearDown(controller.dispose);
      await flush();
      autoProbed = List.of(probed);
      probed.clear();
      answer = probeOk;
      return controller;
    }

    DiscoveredServer casa(String id) =>
        server('Casa', addresses: ['10.0.0.1'], id: id);

    test('o primeiro contato é testado, entra e fica lembrado', () async {
      await makeTrusted([casa('aaa')]);
      expect(autoProbed, [casa('aaa').baseUri]);
      expect(controller.current.selected?.name, 'Casa');
      expect(trust.trustOf('Casa', 'aaa'), Trust.same);
    });

    test('outro id sob o mesmo nome pergunta antes e não sonda', () async {
      await makeTrusted([
        server('Nuvem', addresses: ['10.0.0.9']),
      ]);
      await trust.remember('Casa', 'aaa');
      discovery.emit([
        casa('bbb'),
        server('Nuvem', addresses: ['10.0.0.9']),
      ]);
      await flush();

      final changed = controller.current.available.firstWhere(
        (s) => s.name == 'Casa',
      );
      expect(await controller.select(changed), isTrue, reason: 'nada falhou');
      expect(controller.current.pendingChange, changed);
      expect(controller.current.selected?.name, 'Nuvem');
      expect(probed, isEmpty);
    });

    test('cancelar fecha a pergunta e deixa tudo como estava', () async {
      await makeTrusted([
        server('Nuvem', addresses: ['10.0.0.9']),
      ]);
      await trust.remember('Casa', 'aaa');
      discovery.emit([
        casa('bbb'),
        server('Nuvem', addresses: ['10.0.0.9']),
      ]);
      await flush();
      await controller.select(
        controller.current.available.firstWhere((s) => s.name == 'Casa'),
      );
      controller.cancelChange();
      expect(controller.current.pendingChange, isNull);
      expect(controller.current.selected?.name, 'Nuvem');
      expect(trust.trustOf('Casa', 'aaa'), Trust.same);
    });

    test('confirmar sonda, escolhe e passa a lembrar do novo id', () async {
      await makeTrusted([
        server('Nuvem', addresses: ['10.0.0.9']),
      ]);
      await trust.remember('Casa', 'aaa');
      discovery.emit([
        casa('bbb'),
        server('Nuvem', addresses: ['10.0.0.9']),
      ]);
      await flush();
      await controller.select(
        controller.current.available.firstWhere((s) => s.name == 'Casa'),
      );
      expect(await controller.confirmChange(), isTrue);
      expect(controller.current.pendingChange, isNull);
      expect(controller.current.selected?.name, 'Casa');
      expect(probed, hasLength(1));
      expect(trust.trustOf('Casa', 'bbb'), Trust.same);
    });

    test(
      'confirmar um servidor que não responde mantém a escolha anterior e não o lembra',
      () async {
        await makeTrusted([
          server('Nuvem', addresses: ['10.0.0.9']),
        ], probeOk: false);
        await trust.remember('Casa', 'aaa');
        discovery.emit([
          casa('bbb'),
          server('Nuvem', addresses: ['10.0.0.9']),
        ]);
        await flush();
        await controller.select(
          controller.current.available.firstWhere((s) => s.name == 'Casa'),
        );
        expect(await controller.confirmChange(), isFalse);
        expect(controller.current.selected?.name, 'Nuvem');
        expect(trust.trustOf('Casa', 'aaa'), Trust.same);
      },
    );

    test(
      'com a pergunta aberta, outros toques não empilham perguntas nem escolhem',
      () async {
        await makeTrusted([
          server('Nuvem', addresses: ['10.0.0.9']),
        ]);
        await trust.remember('Casa', 'aaa');
        discovery.emit([
          casa('bbb'),
          server('Nuvem', addresses: ['10.0.0.9']),
          server('Outro', addresses: ['10.0.0.7']),
        ]);
        await flush();
        final changed = controller.current.available.firstWhere(
          (s) => s.name == 'Casa',
        );
        await controller.select(changed);
        for (var i = 0; i < 5; i++) {
          await controller.select(
            controller.current.available.firstWhere((s) => s.name == 'Outro'),
          );
          await controller.select(changed);
        }
        expect(controller.current.pendingChange, changed);
        expect(controller.current.selected?.name, 'Nuvem');
        expect(probed, isEmpty);
      },
    );

    test('confirmar ou cancelar sem pergunta aberta não faz nada', () async {
      await makeTrusted([casa('aaa')]);
      final before = controller.current.selected;
      expect(await controller.confirmChange(), isTrue);
      controller.cancelChange();
      expect(controller.current.selected, before);
      expect(probed, isEmpty);
    });

    test('um nome que mudou de id não entra: a pessoa é perguntada, e nada é escolhido', () async {
      trust = ServerTrust(MemoryKeyValueStore());
      await trust.remember('Casa', 'aaa');
      discovery = FakeDiscovery([casa('bbb')]);
      controller = ServerListController(
        discovery: discovery,
        trust: trust,
      );
      pickFirst(controller);
      addTearDown(controller.dispose);
      await flush();
      expect(controller.current.selected, isNull);
      expect(controller.current.pendingChange?.name, 'Casa');
      expect(controller.current.available, hasLength(1));
    });

    test(
      'o escolhido que passa a anunciar outro id deixa de estar conectado, não é trocado em silêncio',
      () async {
        await makeTrusted([casa('aaa')]);
        expect(controller.current.connection, ServerConnection.connected);
        discovery.emit([casa('zzz')]);
        await flush();
        expect(controller.current.selected?.serverId, 'aaa');
        expect(controller.current.connection, ServerConnection.disconnected);
        expect(controller.current.available.single.serverId, 'zzz');
      },
    );

    test(
      'lista chegando antes de ler o que se lembrava espera por isso',
      () async {
        final slow = _SlowStore();
        await ServerTrust(slow).remember('Casa', 'aaa');
        trust = ServerTrust(slow);
        discovery = FakeDiscovery([casa('bbb')]);
        controller = ServerListController(
          discovery: discovery,
          trust: trust,
        );
        pickFirst(controller);
      addTearDown(controller.dispose);
        expect(controller.current.loaded, isFalse);
        slow.release();
        await flush();
        await flush();
        expect(controller.current.loaded, isTrue);
        expect(
          controller.current.selected,
          isNull,
          reason: 'o nome mudou de id: não se escolhe sozinho',
        );
      },
    );

    test('sem trust tudo funciona como antes', () async {
      make();
      await flush();
      expect(controller.current.pendingChange, isNull);
      expect(controller.current.selected, isNotNull);
    });
  });

  group('confiáveis e pareados', () {
    final pem = File('test/fixtures/pairing/good-ca.pem').readAsStringSync();
    PairedServer paired(String hostPort, {String name = 'Casa', String id = 'aaa'}) =>
        PairedServer(hostPort: hostPort, fingerprint: fingerprintOfPem(pem), caPem: pem, name: name, serverId: id);

    ServerListController build({ServerTrust? trust, PairedStore? store, List<DiscoveredServer>? initial}) {
      discovery = FakeDiscovery(initial ?? sampleServers);
      controller = ServerListController(discovery: discovery, trust: trust, paired: store);
      addTearDown(controller.dispose);
      return controller;
    }

    test('quem já foi aberto com o mesmo id é confiável; o novo e o que mudou de id não são', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      await trust.remember('Casa', 'aaa');
      await trust.remember('Nuvem', 'zzz');
      build(
        trust: trust,
        initial: [
          server('Casa', addresses: ['10.0.0.1'], id: 'aaa'),
          server('Nuvem', addresses: ['10.0.0.9'], id: 'outro'),
          server('Escritório', addresses: ['10.0.0.2'], id: 'bbb'),
        ],
      );
      await flush();
      await flush();
      final byName = {for (final s in controller.current.available) s.name: s};
      expect(byName['Casa']!.trusted, isTrue);
      expect(byName['Nuvem']!.trusted, isFalse, reason: 'same name, another id: not the server the person knows');
      expect(byName['Escritório']!.trusted, isFalse);
      expect(controller.isChanged(byName['Nuvem']!), isTrue);
      expect(controller.isChanged(byName['Escritório']!), isFalse);
      expect(controller.current.selected, isNull, reason: 'nothing is chosen on its own');
    });

    test('concluir o pareamento escolhe o servidor, o lembra e o marca confiável', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      build(trust: trust, initial: [server('Casa', addresses: ['10.0.0.1'], id: 'aaa')]);
      await flush();
      await flush();
      expect(controller.current.available.single.trusted, isFalse);
      await controller.completePairing(ServerOption.fromPaired(paired('10.0.0.1:8443')));
      expect(controller.current.selected?.name, 'Casa');
      expect(controller.current.selected?.trusted, isTrue);
      expect(controller.current.selected?.baseUri?.scheme, 'https');
      expect(trust.trustOf('Casa', 'aaa'), Trust.same, reason: 'remembered for the next time');
      expect(controller.current.available.where((s) => s.name == 'Casa'), hasLength(1), reason: 'no duplicate of the announced one');
      expect(controller.current.available.single.trusted, isTrue);
    });

    test('concluir o pareamento de um nome que mudou de id fecha a pergunta pendente', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      await trust.remember('Casa', 'velho');
      build(trust: trust, initial: [server('Casa', addresses: ['10.0.0.1'], id: 'novo')]);
      await flush();
      await flush();
      await controller.select(controller.current.available.single);
      expect(controller.current.pendingChange, isNotNull);
      await controller.completePairing(ServerOption.fromPaired(paired('10.0.0.1:8443', id: 'novo')));
      expect(controller.current.pendingChange, isNull);
      expect(controller.current.selected?.name, 'Casa');
      expect(trust.trustOf('Casa', 'novo'), Trust.same);
    });

    test('os servidores pareados aparecem mesmo sem serem anunciados, e não duplicam os anunciados', () async {
      final store = MemoryPairedStore();
      await store.save(paired('192.168.1.50:8443', name: 'Sítio', id: 'sss'));
      await store.save(paired('10.0.0.1:8443', name: 'Casa', id: ''));
      build(store: store, initial: [server('Casa', addresses: ['10.0.0.1'])]);
      await flush();
      await flush();
      final names = controller.current.available.map((s) => s.name).toList();
      expect(names, ['Casa', 'Sítio']);
      final sitio = controller.current.available.last;
      expect(sitio.trusted, isTrue);
      expect(sitio.baseUri, Uri.parse('https://192.168.1.50:8443'));
      expect(controller.current.selected, isNull);
    });

    test('um servidor pareado continua na lista quando a rede deixa de anunciá-lo', () async {
      final store = MemoryPairedStore();
      await store.save(paired('10.0.0.1:8443', name: 'Casa', id: ''));
      build(store: store, initial: [server('Casa', addresses: ['10.0.0.1'])]);
      await flush();
      await flush();
      discovery.emit(const []);
      await flush();
      expect(controller.current.available.map((s) => s.name), ['Casa']);
    });

    test('o nome dado pela pessoa aparece, mas o servidor continua lembrado pelo nome que ele anuncia', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      build(trust: trust, initial: [server('Casa', addresses: ['10.0.0.1'], id: 'aaa')]);
      await flush();
      await flush();
      await controller.completePairing(ServerOption.fromPaired(paired('10.0.0.1:8443').withLabel('Sala de estar')));
      expect(controller.current.selected?.name, 'Sala de estar');
      expect(trust.trustOf('Casa', 'aaa'), Trust.same);
      expect(trust.trustOf('Sala de estar', 'aaa'), Trust.unknown);
      expect(controller.current.available.single.name, 'Sala de estar', reason: 'the announced one takes the given name');
      discovery.emit([server('Casa', addresses: ['10.0.0.1'], id: 'aaa')]);
      await flush();
      expect(controller.current.available.single.name, 'Sala de estar', reason: 'and keeps it when the list is refreshed');
    });

    test('limpar o nome: controle, espaços repetidos e tamanho', () {
      expect(cleanLabel('  a\u0000b\n\tc   d  '), 'a b c d');
      expect(cleanLabel(''), '');
      expect(cleanLabel('   '), '');
      expect(cleanLabel('x' * 100).length, PairingCode.maxNameLength);
      expect(cleanLabel('${'x' * 63}  y'), 'x' * 63, reason: 'cut at the limit, no trailing space');
      expect(paired('1.2.3.4:8443').withLabel('Meu').shownName, 'Meu');
      expect(paired('1.2.3.4:8443').shownName, 'Casa');
    });

    test('retirar a confiança: esquece o pareamento e o nome, deixa de ser o escolhido e volta a pedir pareamento', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      final store = MemoryPairedStore();
      await trust.remember('Casa', 'aaa');
      await store.save(paired('10.0.0.1:8443'));
      build(trust: trust, store: store, initial: [server('Casa', addresses: ['10.0.0.1'], id: 'aaa')]);
      await flush();
      await flush();
      final casa = controller.current.available.single;
      expect(casa.trusted, isTrue);
      await controller.select(casa);
      expect(controller.current.selected?.name, 'Casa');

      await controller.revokeTrust(casa);
      expect(controller.current.selected, isNull, reason: 'it is not the chosen one any more');
      expect(controller.current.available.single.trusted, isFalse, reason: 'announced: stays, as a new server');
      expect(trust.trustOf('Casa', 'aaa'), Trust.unknown);
      expect(await store.all(), isEmpty, reason: 'its CA is forgotten');
      expect(controller.isChanged(controller.current.available.single), isFalse);
    });

    test('retirar a confiança vale para sempre: um controlador novo sobre o mesmo armazenamento não confia', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      final store = MemoryPairedStore();
      await trust.remember('Casa', 'aaa');
      await store.save(paired('10.0.0.1:8443'));
      build(trust: trust, store: store, initial: [server('Casa', addresses: ['10.0.0.1'], id: 'aaa')]);
      await flush();
      await flush();
      await controller.revokeTrust(controller.current.available.single);
      await controller.dispose();
      final again = ServerListController(discovery: FakeDiscovery([server('Casa', addresses: ['10.0.0.1'], id: 'aaa')]), trust: trust, paired: store);
      addTearDown(again.dispose);
      await flush();
      await flush();
      expect(again.current.available.single.trusted, isFalse);
    });

    test('um servidor só conhecido pelo pareamento (não anunciado) some ao retirar a confiança', () async {
      final store = MemoryPairedStore();
      await store.save(paired('192.168.1.50:8443', name: 'Sítio', id: 'sss'));
      build(store: store, initial: const []);
      await flush();
      await flush();
      final sitio = controller.current.available.single;
      await controller.select(sitio);
      expect(controller.current.selected?.name, 'Sítio');
      await controller.revokeTrust(sitio);
      expect(controller.current.available, isEmpty);
      expect(controller.current.selected, isNull);
      expect(await store.all(), isEmpty);
    });

    test('depois de retirar a confiança dá para parear de novo', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      final store = MemoryPairedStore();
      await trust.remember('Casa', 'aaa');
      await store.save(paired('10.0.0.1:8443'));
      build(trust: trust, store: store, initial: [server('Casa', addresses: ['10.0.0.1'], id: 'aaa')]);
      await flush();
      await flush();
      await controller.revokeTrust(controller.current.available.single);
      await controller.completePairing(ServerOption.fromPaired(paired('10.0.0.1:8443')));
      expect(controller.current.selected?.trusted, isTrue);
      expect(trust.trustOf('Casa', 'aaa'), Trust.same);
    });

    test('retirar a confiança só do que se pediu: os outros continuam confiáveis', () async {
      final trust = ServerTrust(MemoryKeyValueStore());
      await trust.remember('Casa', 'aaa');
      await trust.remember('Nuvem', 'nnn');
      build(
        trust: trust,
        initial: [server('Casa', addresses: ['10.0.0.1'], id: 'aaa'), server('Nuvem', addresses: ['10.0.0.9'], id: 'nnn')],
      );
      await flush();
      await flush();
      final casa = controller.current.available.firstWhere((s) => s.name == 'Casa');
      await controller.revokeTrust(casa);
      final byName = {for (final s in controller.current.available) s.name: s.trusted};
      expect(byName, {'Casa': false, 'Nuvem': true});
    });

    test('retirar duas vezes, ou de quem nunca foi confiável, ou com o armazenamento falhando, não quebra', () async {
      build(initial: [server('Casa', addresses: ['10.0.0.1'])], store: _FailingStore());
      await flush();
      await flush();
      final casa = controller.current.available.single;
      await Future.wait([controller.revokeTrust(casa), controller.revokeTrust(casa)]);
      await controller.revokeTrust(ServerOption.fromDiscovered(server('Fantasma', addresses: ['10.9.9.9'])));
      expect(controller.current.available, hasLength(1));
    });

    testWidgets('um armazenamento que nunca responde não impede a lista de aparecer (depois do limite)', (tester) async {
      discovery = FakeDiscovery(sampleServers);
      controller = ServerListController(discovery: discovery, paired: _HangingStore());
      addTearDown(controller.dispose);
      await tester.pump();
      expect(controller.current.loaded, isFalse);
      await tester.pump(ServerListController.loadTimeout + const Duration(milliseconds: 10));
      await tester.pump();
      expect(controller.current.available, hasLength(3));
    });

    test('concluir o pareamento duas vezes seguidas, ou com a tela já fechada, não quebra', () async {
      build(initial: [server('Casa', addresses: ['10.0.0.1'])]);
      await flush();
      final p = ServerOption.fromPaired(paired('10.0.0.1:8443'));
      await Future.wait([controller.completePairing(p), controller.completePairing(p)]);
      expect(controller.current.selected?.name, 'Casa');
      expect(controller.current.available, hasLength(1));
    });
  });

  group('pausa com o app em segundo plano', () {
    late PausableDiscovery pausable;

    ServerListController makePausable({List<DiscoveredServer>? initial}) {
      pausable = PausableDiscovery(initial ?? sampleServers);
      controller = ServerListController(
        discovery: pausable,
      );
      pickFirst(controller);
      addTearDown(controller.dispose);
      return controller;
    }

    test('pausar pausa a busca; retomar a retoma', () async {
      makePausable();
      await flush();
      controller.pause();
      expect(pausable.pauses, 1);
      controller.resume();
      expect(pausable.resumes, 1);
    });

    test('pausar e retomar várias vezes seguidas não confunde', () async {
      makePausable();
      await flush();
      controller
        ..pause()
        ..pause()
        ..pause();
      expect(pausable.pauses, 1);
      controller
        ..resume()
        ..resume();
      expect(pausable.resumes, 1);
      controller.resume();
      expect(
        pausable.resumes,
        1,
        reason: 'retomar sem estar pausado não faz nada',
      );
    });

    test('a escolha continua enquanto pausado', () async {
      makePausable();
      await flush();
      final before = controller.current.selected;
      controller.pause();
      await flush();
      expect(controller.current.selected, before);
      expect(controller.current.connection, ServerConnection.connected);
    });

    test('sem escolha, ao retomar sorteia com o que já se sabia', () async {
      makePausable(initial: const []);
      await flush();
      controller.pause();
      pausable.out.add(sampleServers); // buffered while paused
      await flush();
      expect(controller.current.selected, isNull);
      controller.resume();
      await flush();
      expect(controller.current.selected?.name, 'Casa');
    });

    test('pausar e fechar em seguida não quebra', () async {
      makePausable();
      await flush();
      controller.pause();
      await controller.dispose();
      controller.resume();
      controller.pause();
    });
  });
}

/// A store that only answers reads after [release]: the first list arrives before what was remembered is read.
class _SlowStore implements KeyValueStore {
  final _data = <String, String>{};
  final _gate = Completer<void>();
  bool _open = false;

  void release() {
    _open = true;
    _gate.complete();
  }

  @override
  Future<String?> read(String key) async {
    if (!_open) await _gate.future;
    return _data[key];
  }

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

/// A device whose secure storage never answers.
class _HangingStore implements PairedStore {
  @override
  Future<List<PairedServer>> all() => Completer<List<PairedServer>>().future;

  @override
  Future<PairedServer?> find(String hostPort) => Completer<PairedServer?>().future;

  @override
  Future<void> save(PairedServer server) => Completer<void>().future;

  @override
  Future<void> forget(String hostPort) => Completer<void>().future;
}

/// A paired-servers store that fails when asked.
class _FailingStore implements PairedStore {
  @override
  Future<List<PairedServer>> all() async => throw StateError('no storage');

  @override
  Future<PairedServer?> find(String hostPort) async => throw StateError('no storage');

  @override
  Future<void> save(PairedServer server) async => throw StateError('no storage');

  @override
  Future<void> forget(String hostPort) async => throw StateError('no storage');
}
