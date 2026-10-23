import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/nsd_discovery.dart';
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
  }) => listener!(
    nsd.ServiceStatus.found,
    nsd.Service(
      name: name,
      type: '_plany._tcp',
      host: host,
      port: port,
      addresses: [for (final ip in ips) InternetAddress(ip)],
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
    NsdDiscovery? discovery,
  }) async {
    final d = discovery ?? NsdDiscovery(api: api, restartWhileEmpty: restart);
    sub = d.watch().listen(emitted.add, onError: errors.add);
    await settle();
  }

  setUp(() {
    api = FakeNsdApi();
    emitted = [];
    errors = [];
  });

  tearDown(() => sub.cancel());

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
    expect(emitted.last.map((s) => s.name), ['Zeta']);
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
}
