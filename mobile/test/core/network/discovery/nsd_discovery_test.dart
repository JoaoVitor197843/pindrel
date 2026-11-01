import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/nsd_discovery.dart';
import 'package:mobile/core/network/discovery/server_table.dart';
import 'package:nsd/nsd.dart' as nsd;

class FakeNsdApi implements NsdApi {
  int starts = 0;
  int stops = 0;
  String? type;
  Object? failWith;
  Completer<void>? startGate;
  void Function(nsd.ServiceStatus, nsd.Service)? listener;

  @override
  Future<Object> startDiscovery(
    String serviceType,
    void Function(nsd.ServiceStatus, nsd.Service) listener,
  ) async {
    await startGate?.future;
    if (failWith != null) throw failWith!;
    starts++;
    type = serviceType;
    this.listener = listener;
    return starts;
  }

  @override
  Future<void> stopDiscovery(Object session) async => stops++;

  void found(
    String? name, {
    String? host,
    int? port = 8080,
    List<String> ips = const [],
    Map<String, Uint8List?>? txt,
  }) => listener!(
    nsd.ServiceStatus.found,
    nsd.Service(
      name: name,
      type: '_plany._tcp',
      host: host,
      port: port,
      addresses: [for (final ip in ips) InternetAddress(ip)],
      txt: txt,
    ),
  );

  void lost(String name) => listener!(
    nsd.ServiceStatus.lost,
    nsd.Service(name: name, type: '_plany._tcp'),
  );
}

const _tick = Duration(milliseconds: 15);

Future<void> settle() => Future<void>.delayed(_tick);

void main() {
  late FakeNsdApi api;
  late List<List<DiscoveredServer>> emitted;
  late List<Object> errors;
  late StreamSubscription<List<DiscoveredServer>> sub;

  Future<void> listen({
    Duration restart = const Duration(hours: 1),
    Duration grace = const Duration(milliseconds: 30),
    NsdDiscovery? discovery,
  }) async {
    final d =
        discovery ??
        NsdDiscovery(api: api, restartWhileEmpty: restart, lostGrace: grace);
    sub = d.watch().listen(emitted.add, onError: errors.add);
    await settle();
  }

  setUp(() {
    api = FakeNsdApi();
    emitted = [];
    errors = [];
  });

  tearDown(() => sub.cancel());

  test(
    'o id do registro TXT chega ao servidor; id estranho é ignorado',
    () async {
      await listen();
      api.found(
        'Casa',
        host: 'casa.local.',
        ips: ['192.168.1.5'],
        txt: {'id': Uint8List.fromList(utf8.encode('abc123'))},
      );
      api.found(
        'Falso',
        host: 'falso.local.',
        ips: ['192.168.1.6'],
        txt: {'id': Uint8List.fromList(utf8.encode('<script>'))},
      );
      api.found('Velho', host: 'velho.local.', ips: ['192.168.1.7']);
      await settle();
      final byName = {for (final s in emitted.last) s.name: s.id};
      expect(byName, {'Casa': 'abc123', 'Falso': '', 'Velho': ''});
    },
  );

  test(
    'o mesmo servidor anunciando outro id é uma mudança que chega à lista',
    () async {
      await listen();
      api.found(
        'Casa',
        ips: ['192.168.1.5'],
        txt: {'id': Uint8List.fromList(utf8.encode('aaa'))},
      );
      await settle();
      api.found(
        'Casa',
        ips: ['192.168.1.5'],
        txt: {'id': Uint8List.fromList(utf8.encode('bbb'))},
      );
      await settle();
      expect(emitted.last.single.id, 'bbb');
    },
  );

  test('procura _plany._tcp e já emite a lista vazia', () async {
    await listen();
    expect(api.type, '_plany._tcp');
    expect(api.starts, 1);
    expect(emitted, [<DiscoveredServer>[]]);
  });

  test(
    'um serviço achado vira servidor; o ".local." do host é tirado',
    () async {
      await listen();
      api.found(
        'Plany',
        host: 'raspberry-joao.local.',
        port: 8095,
        ips: ['192.168.1.116'],
      );
      await settle();
      expect(emitted.last, [
        const DiscoveredServer(
          name: 'Plany',
          host: 'raspberry-joao',
          addresses: ['192.168.1.116'],
          port: 8095,
        ),
      ]);
    },
  );

  test(
    'só entram IPv4 utilizáveis (nada de IPv6, loopback ou link-local)',
    () async {
      await listen();
      api.found(
        'A',
        host: 'a.local',
        ips: ['fe80::1', '127.0.0.1', '169.254.1.1', '192.168.1.7', '10.0.0.3'],
      );
      await settle();
      expect(emitted.last.single.addresses, ['10.0.0.3', '192.168.1.7']);
    },
  );

  test('serviço sem nome ou sem porta válida é ignorado', () async {
    await listen();
    api.found(null, host: 'x.local');
    api.found('', host: 'x.local');
    api.found('SemPorta', host: 'x.local', port: null);
    api.found('PortaZero', host: 'x.local', port: 0);
    api.found('PortaGrande', host: 'x.local', port: 70000);
    await settle();
    expect(emitted, [<DiscoveredServer>[]], reason: 'nada novo para emitir');
  });

  test(
    'não repete a emissão quando nada mudou, e substitui o que mudou',
    () async {
      await listen();
      api.found('A', host: 'a.local', ips: ['10.0.0.1']);
      api.found('A', host: 'a.local', ips: ['10.0.0.1']);
      await settle();
      expect(emitted.length, 2, reason: 'vazia + um servidor');
      api.found('A', host: 'a.local', ips: ['10.0.0.9']);
      await settle();
      expect(emitted.length, 3);
      expect(emitted.last.single.addresses, ['10.0.0.9']);
    },
  );

  test('a lista sai ordenada e um serviço perdido sai dela', () async {
    await listen();
    api.found('Zeta', host: 'z.local', ips: ['10.0.0.2']);
    api.found('Alfa', host: 'a.local', ips: ['10.0.0.1']);
    await settle();
    expect(emitted.last.map((s) => s.name), ['Alfa', 'Zeta']);
    api.lost('Alfa');
    api.lost('Inexistente');
    await settle();
    expect(emitted.last.map((s) => s.name), [
      'Alfa',
      'Zeta',
    ], reason: 'perdido não sai na hora');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(emitted.last.map((s) => s.name), ['Zeta']);
  });

  test(
    'um "perdido" falso, achado de novo no prazo, não muda a lista',
    () async {
      await listen(grace: const Duration(milliseconds: 60));
      api.found('A', host: 'a.local', ips: ['10.0.0.1']);
      await settle();
      final count = emitted.length;
      api.lost('A');
      await settle();
      api.found('A', host: 'a.local', ips: ['10.0.0.1']);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(emitted.length, count, reason: 'nenhuma emissão nova');
      expect(emitted.last.single.name, 'A');
    },
  );

  test('com um servidor perdido, reinicia a busca para achá-lo', () async {
    await listen(
      restart: const Duration(milliseconds: 20),
      grace: const Duration(milliseconds: 200),
    );
    api.found('A', host: 'a.local', ips: ['10.0.0.1']);
    await settle();
    final starts = api.starts;
    api.lost('A');
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(api.starts, greaterThan(starts));
  });

  test('a tabela tem teto: anúncios em enxurrada não a enchem', () async {
    await listen();
    for (var i = 0; i < 500; i++) {
      api.found('S$i', host: 'h$i.local', ips: ['10.0.0.${i % 250 + 1}']);
    }
    api.found('N' * 500, host: 'x.local', ips: ['10.0.0.1']);
    await settle();
    expect(emitted.last.length, ServerTable.defaultMaxServers);
  });

  test(
    'enquanto nada foi achado, reinicia a busca de tempos em tempos',
    () async {
      await listen(restart: const Duration(milliseconds: 40));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(api.starts, greaterThanOrEqualTo(3));
      expect(
        api.stops,
        api.starts - 1,
        reason: 'cada reinício para a anterior',
      );
    },
  );

  test('depois de achar algo, deixa a busca em paz', () async {
    await listen(restart: const Duration(milliseconds: 40));
    api.found('A', host: 'a.local', ips: ['10.0.0.1']);
    await settle();
    final starts = api.starts;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(api.starts, starts);
    expect(api.stops, 0);
  });

  test('cancelar a escuta para a busca e não emite mais', () async {
    await listen();
    await sub.cancel();
    expect(api.stops, 1);
    final before = emitted.length;
    api.found('Tarde', host: 't.local', ips: ['10.0.0.5']);
    await settle();
    expect(emitted.length, before);
  });

  test('cancelar antes de a busca ter começado também a para', () async {
    api.startGate = Completer<void>();
    sub = NsdDiscovery(api: api).watch().listen(emitted.add);
    await settle();
    await sub.cancel();
    api.startGate!.complete();
    await settle();
    expect(
      api.stops,
      1,
      reason: 'a busca que chegou depois do cancelamento é parada',
    );
  });

  test(
    'falha ao começar (por exemplo, sem permissão) sai como erro do stream',
    () async {
      api.failWith = StateError('sem permissão de rede');
      await listen();
      expect(errors.single, isA<StateError>());
      expect(emitted, [<DiscoveredServer>[]]);
    },
  );

  group('política de reinício, pausa e erros', () {
    NsdDiscovery make({
      Duration restart = const Duration(milliseconds: 20),
      Duration max = const Duration(hours: 1),
      Duration grace = const Duration(milliseconds: 60),
    }) => NsdDiscovery(
      api: api,
      restartWhileEmpty: restart,
      maxRestartDelay: max,
      lostGrace: grace,
    );

    Future<void> listenTo(NsdDiscovery d) async {
      sub = d.watch().listen(emitted.add, onError: errors.add);
      await settle();
    }

    test('rede vazia: a espera entre reinícios cresce, não é fixa', () async {
      await listenTo(make());
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // fixed 20 ms would restart about 12 times; doubling (20, 40, 80, 160) about 3
      expect(api.starts, inInclusiveRange(3, 6));
    });

    test('o teto limita a espera', () async {
      await listenTo(
        make(
          restart: const Duration(milliseconds: 10),
          max: const Duration(milliseconds: 20),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(api.starts, greaterThan(6));
    });

    test('pausar para a busca e nenhum reinício acontece pausado', () async {
      await listenTo(make());
      sub.pause();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final starts = api.starts;
      expect(api.stops, 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(api.starts, starts);
      expect(api.stops, 1);
    });

    test(
      'retomar começa a busca de novo, e pausar duas vezes não quebra',
      () async {
        await listenTo(make());
        sub.pause();
        sub.pause();
        sub.resume();
        await settle();
        expect(api.starts, 1, reason: 'ainda pausado uma vez');
        sub.resume();
        await settle();
        expect(api.starts, 2);
      },
    );

    test(
      'ao retomar, quem não responde sai depois do prazo; quem responde fica',
      () async {
        await listenTo(make(restart: const Duration(hours: 1)));
        api.found('Fica', host: 'a.local', ips: ['10.0.0.1']);
        api.found('Some', host: 'b.local', ips: ['10.0.0.2']);
        await settle();
        sub.pause();
        sub.resume();
        await settle();
        api.found('Fica', host: 'a.local', ips: ['10.0.0.1']);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(emitted.last.map((s) => s.name), ['Fica']);
      },
    );

    test('pausar durante o início não deixa uma busca ligada', () async {
      api.startGate = Completer<void>();
      sub = make().watch().listen(emitted.add, onError: errors.add);
      await settle();
      sub.pause();
      api.startGate!.complete();
      await settle();
      expect(
        api.stops,
        1,
        reason: 'a busca que chegou durante a pausa é parada',
      );
    });

    test('o primeiro início que falha é tentado de novo depois', () async {
      api.failWith = StateError('sem rede ainda');
      await listenTo(make());
      expect(errors, hasLength(1));
      api.failWith = null;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.starts, greaterThanOrEqualTo(1));
    });

    test('um reinício que falha uma ou duas vezes não vira erro', () async {
      await listenTo(
        make(
          restart: const Duration(milliseconds: 15),
          max: const Duration(milliseconds: 15),
        ),
      );
      api.failWith = StateError('engasgo');
      await Future<void>.delayed(const Duration(milliseconds: 22));
      api.failWith = null;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(errors, isEmpty);
    });

    test('um reinício que falha sem parar vira um erro só', () async {
      await listenTo(
        make(
          restart: const Duration(milliseconds: 10),
          max: const Duration(milliseconds: 10),
        ),
      );
      api.failWith = StateError('sem permissão');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(errors, hasLength(1));
    });

    test('pausar e retomar durante o início não abre duas buscas', () async {
      api.startGate = Completer<void>();
      sub = make().watch().listen(emitted.add, onError: errors.add);
      await settle();
      sub.pause();
      sub.resume();
      api.startGate!.complete();
      await settle();
      expect(api.starts, 1);
      await sub.cancel();
      await settle();
      expect(api.stops, 1, reason: 'a única busca aberta é parada ao cancelar');
    });
  });
}
