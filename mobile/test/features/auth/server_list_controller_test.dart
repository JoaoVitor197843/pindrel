import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/server_discovery.dart';
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

void main() {
  late FakeDiscovery discovery;
  late ServerListController controller;

  ServerListController make({int random = 0, List<DiscoveredServer>? initial}) {
    discovery = FakeDiscovery(initial ?? sampleServers);
    controller = ServerListController(
      discovery: discovery,
      random: FixedRandom(random),
    );
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

    test('sorteia um dos achados, e o sorteio decide qual', () async {
      for (final (random, name) in [
        (0, 'Casa'),
        (1, 'Escritório'),
        (2, 'Nuvem'),
        (4, 'Escritório'),
      ]) {
        make(random: random);
        await flush();
        expect(
          controller.current.selected?.name,
          name,
          reason: 'sorteio $random',
        );
        expect(controller.current.connection, ServerConnection.connected);
      }
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
      make(random: 1);
      await flush();
      expect(controller.current.selected?.name, 'Escritório');
      discovery.emit([
        server('Aaa', addresses: ['10.0.0.1']),
        ...sampleServers,
      ]);
      await flush();
      expect(controller.current.selected?.name, 'Escritório');
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
      final c = ServerListController(discovery: d, random: FixedRandom(0));
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
      final c = ServerListController(discovery: d, random: FixedRandom(0));
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
    ServerListController makeProbed(Future<bool> Function(Uri) probe) {
      discovery = FakeDiscovery(sampleServers);
      controller = ServerListController(
        discovery: discovery,
        random: FixedRandom(0),
        probe: probe,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('responde: escolhe, e connecting aparece enquanto espera', () async {
      final gate = Completer<bool>();
      Uri? asked;
      makeProbed((uri) {
        asked = uri;
        return gate.future;
      });
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
        random: FixedRandom(random),
        trust: trust,
        probe: (uri) async {
          probed.add(uri);
          return answer;
        },
      );
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

    test(
      'o sorteio inicial nunca escolhe sozinho um nome que mudou de id',
      () async {
        trust = ServerTrust(MemoryKeyValueStore());
        await trust.remember('Casa', 'aaa');
        discovery = FakeDiscovery([
          casa('bbb'),
          server('Nuvem', addresses: ['10.0.0.9']),
        ]);
        controller = ServerListController(
          discovery: discovery,
          random: FixedRandom(0),
          trust: trust,
        );
        addTearDown(controller.dispose);
        await flush();
        expect(controller.current.selected?.name, 'Nuvem');
      },
    );

    test('se só há nomes que mudaram, nada é escolhido sozinho', () async {
      trust = ServerTrust(MemoryKeyValueStore());
      await trust.remember('Casa', 'aaa');
      discovery = FakeDiscovery([casa('bbb')]);
      controller = ServerListController(
        discovery: discovery,
        random: FixedRandom(0),
        trust: trust,
      );
      addTearDown(controller.dispose);
      await flush();
      expect(controller.current.selected, isNull);
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
          random: FixedRandom(0),
          trust: trust,
        );
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

  group('escolha automática testada no início', () {
    const retry = Duration(milliseconds: 30);

    ServerListController makeAuto(
      Future<bool> Function(Uri) probe, {
      List<DiscoveredServer>? initial,
      int random = 0,
    }) {
      discovery = FakeDiscovery(initial ?? sampleServers);
      controller = ServerListController(
        discovery: discovery,
        random: FixedRandom(random),
        probe: probe,
        autoRetry: retry,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('o sorteado é testado antes de ser escolhido', () async {
      final gate = Completer<bool>();
      Uri? asked;
      makeAuto((uri) {
        asked = uri;
        return gate.future;
      });
      await flush();
      expect(asked, sampleServers.first.baseUri);
      expect(controller.current.selected, isNull, reason: 'ainda testando');
      expect(controller.current.available, hasLength(3));
      gate.complete(true);
      await flush();
      expect(controller.current.selected?.name, 'Casa');
      expect(controller.current.connection, ServerConnection.connected);
    });

    test('se o sorteado não responde, tenta o próximo', () async {
      final asked = <String>[];
      makeAuto((uri) async {
        asked.add(uri.host);
        return uri.host == '192.168.0.20';
      });
      await flush();
      await flush();
      expect(controller.current.selected?.name, 'Escritório');
      expect(asked.length, 2);
    });

    test('um que lança é tratado como não respondeu', () async {
      var calls = 0;
      makeAuto((_) async {
        if (calls++ == 0) throw StateError('boom');
        return true;
      });
      await flush();
      await flush();
      expect(controller.current.selected, isNotNull);
      expect(calls, 2);
    });

    test(
      'ninguém responde: sem escolha, no máximo 3 testes por rodada',
      () async {
        var calls = 0;
        makeAuto(
          (_) async {
            calls++;
            return false;
          },
          initial: [
            for (var i = 0; i < 6; i++)
              server('S$i', addresses: ['10.0.0.${i + 1}']),
          ],
        );
        await flush();
        await flush();
        expect(controller.current.selected, isNull);
        expect(controller.current.available, hasLength(6));
        expect(calls, ServerListController.maxAutoProbes);
      },
    );

    test('depois de uma rodada sem resposta, tenta de novo sozinho', () async {
      var up = false;
      makeAuto((_) async => up);
      await flush();
      expect(controller.current.selected, isNull);
      up = true;
      await Future<void>.delayed(retry * 3);
      expect(controller.current.selected, isNotNull);
    });

    test(
      'o usuário escolhe durante o teste: o resultado do teste é descartado',
      () async {
        final gate = Completer<bool>();
        var calls = 0;
        makeAuto((_) {
          calls++;
          return calls == 1 ? gate.future : Future.value(true);
        });
        await flush();
        final mine = controller.current.available.last;
        expect(await controller.select(mine), isTrue);
        gate.complete(true);
        await flush();
        expect(controller.current.selected, mine);
      },
    );

    test(
      'lista chegando de novo durante o teste não dispara outro teste',
      () async {
        final gate = Completer<bool>();
        var calls = 0;
        makeAuto((_) {
          calls++;
          return gate.future;
        });
        await flush();
        for (var i = 0; i < 10; i++) {
          discovery.emit([
            ...sampleServers,
            server('Extra$i', addresses: ['10.1.0.$i']),
          ]);
          await flush();
        }
        expect(calls, 1);
        gate.complete(true);
        await flush();
        expect(controller.current.selected, isNotNull);
      },
    );

    test(
      'fechar a tela durante o teste não escolhe nada nem deixa timer',
      () async {
        final gate = Completer<bool>();
        makeAuto((_) => gate.future);
        await flush();
        await controller.dispose();
        gate.complete(true);
        await flush();
        expect(controller.current.selected, isNull);
      },
    );
  });

  group('pausa com o app em segundo plano', () {
    late PausableDiscovery pausable;

    ServerListController makePausable({List<DiscoveredServer>? initial}) {
      pausable = PausableDiscovery(initial ?? sampleServers);
      controller = ServerListController(
        discovery: pausable,
        random: FixedRandom(0),
      );
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
