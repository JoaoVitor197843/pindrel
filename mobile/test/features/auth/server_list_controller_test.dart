import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/server_discovery.dart';
import 'package:mobile/features/auth/data/server_list_controller.dart';
import 'package:mobile/features/auth/data/server_list_state.dart';
import 'package:mobile/features/auth/data/server_option.dart';

import '../../support/discovery_fakes.dart';

/// Uma descoberta que também pode falhar.
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
        ]); // sai o Escritório
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
}
