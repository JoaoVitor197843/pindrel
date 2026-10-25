import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/mdns_discovery.dart';
import 'package:mobile/core/network/discovery/server_table.dart';

class FakeMdnsApi implements MdnsApi {
  FakeMdnsApi(this.script);

  /// What each sweep returns; the last one repeats.
  final List<Object> script;
  int scans = 0;
  int stops = 0;
  int starts = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  Duration scanTime = Duration.zero;
  Object? startError;

  @override
  Future<void> start() async {
    starts++;
    if (startError != null) throw startError!;
  }

  @override
  void stop() => stops++;

  @override
  Future<List<MdnsFound>> scan(String serviceType, Duration timeout) async {
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    final step = script[scans < script.length ? scans : script.length - 1];
    scans++;
    await Future<void>.delayed(scanTime);
    concurrent--;
    if (step is Exception) throw step;
    return step as List<MdnsFound>;
  }
}

MdnsFound found(
  String name, {
  String ip = '192.168.1.10',
  int port = 8080,
  String id = '',
}) => MdnsFound(
  name: name,
  host: '$name-host',
  port: port,
  addresses: [ip],
  id: id,
);

const _interval = Duration(milliseconds: 20);

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late List<List<DiscoveredServer>> emitted;
  late List<Object> errors;
  late StreamSubscription<List<DiscoveredServer>> sub;

  MdnsDiscovery make(
    FakeMdnsApi api, {
    Duration grace = const Duration(milliseconds: 70),
    Duration restart = const Duration(hours: 1),
  }) => MdnsDiscovery(
    api: api,
    interval: _interval,
    scanTimeout: _interval,
    lostGrace: grace,
    restartWhileEmpty: restart,
  );

  Future<void> listen(MdnsDiscovery d) async {
    sub = d.watch().listen(emitted.add, onError: errors.add);
  }

  setUp(() {
    emitted = [];
    errors = [];
  });

  tearDown(() => sub.cancel());

  test(
    'emite vazia, varre logo ao começar e emite o que achou, ordenado',
    () async {
      final api = FakeMdnsApi([
        [found('Zeta', ip: '10.0.0.2'), found('Alfa', ip: '10.0.0.1')],
      ]);
      await listen(make(api));
      await wait(60);
      expect(emitted.first, isEmpty);
      expect(emitted.last.map((s) => s.name), ['Alfa', 'Zeta']);
      expect(emitted.last.first.host, 'Alfa-host');
      expect(emitted.last.first.addresses, ['10.0.0.1']);
    },
  );

  test('o id do TXT chega ao servidor e um id inútil vira vazio', () async {
    final api = FakeMdnsApi([
      [
        found('Casa', ip: '10.0.0.1', id: 'abc123'),
        found('Falso', ip: '10.0.0.2', id: 'com espaço'),
        found('Velho', ip: '10.0.0.3'),
      ],
    ]);
    await listen(make(api));
    await wait(60);
    expect(
      {for (final s in emitted.last) s.name: s.id},
      {'Casa': 'abc123', 'Falso': '', 'Velho': ''},
    );
  });

  test(
    'varre de novo a cada intervalo, sem re-emitir o que não mudou',
    () async {
      final api = FakeMdnsApi([
        [found('A')],
      ]);
      await listen(make(api));
      await wait(150);
      expect(api.scans, greaterThanOrEqualTo(3));
      expect(emitted.length, 2, reason: 'vazia + o servidor, uma vez só');
    },
  );

  test('filtra endereços inválidos e portas inválidas', () async {
    final api = FakeMdnsApi([
      [
        MdnsFound(
          name: 'A',
          host: 'a',
          port: 8080,
          addresses: ['127.0.0.1', '10.0.0.4'],
        ),
        found('PortaZero', port: 0),
        found('PortaGrande', port: 99999),
      ],
    ]);
    await listen(make(api));
    await wait(60);
    expect(emitted.last.map((s) => s.name), ['A']);
    expect(emitted.last.single.addresses, ['10.0.0.4']);
  });

  test('um servidor só sai depois de ficar perdido por todo o prazo', () async {
    final api = FakeMdnsApi([
      [found('A')],
      <MdnsFound>[],
      <MdnsFound>[],
      [found('A')], // came back: the lost mark goes away
      <MdnsFound>[],
    ]);
    await listen(make(api));
    await wait(25 * 4);
    expect(emitted.last.map((s) => s.name), ['A'], reason: 'voltou no prazo');
    await wait(25 * 8);
    expect(emitted.last, isEmpty, reason: 'perdido além do prazo');
  });

  test('com a lista vazia, reinicia o cliente de tempos em tempos', () async {
    final api = FakeMdnsApi([<MdnsFound>[]]);
    await listen(make(api, restart: const Duration(milliseconds: 40)));
    await wait(200);
    expect(api.starts, greaterThanOrEqualTo(3));
    expect(api.stops, api.starts - 1);
  });

  test('depois de achar algo, deixa o cliente em paz', () async {
    final api = FakeMdnsApi([
      [found('A')],
    ]);
    await listen(make(api, restart: const Duration(milliseconds: 40)));
    await wait(200);
    expect(api.starts, 1);
    expect(api.stops, 0);
  });

  test('a tabela tem teto e recusa nomes absurdos', () async {
    final api = FakeMdnsApi([
      [
        for (var i = 0; i < 300; i++) found('S$i', ip: '10.0.${i ~/ 250}.1'),
        found('N' * 500),
      ],
    ]);
    await listen(make(api));
    await wait(80);
    expect(emitted.last.length, ServerTable.defaultMaxServers);
  });

  test('uma varredura que falha vira erro, mas a busca continua', () async {
    final api = FakeMdnsApi([
      [found('A')],
      Exception('rede caiu'),
      [found('A'), found('B')],
    ]);
    await listen(make(api));
    await wait(120);
    expect(errors, isNotEmpty);
    expect(emitted.last.map((s) => s.name), ['A', 'B']);
  });

  test(
    'falha ao iniciar o cliente vira erro e nenhuma varredura é feita',
    () async {
      final api = FakeMdnsApi([<MdnsFound>[]])
        ..startError = StateError('sem rede');
      await listen(make(api));
      await wait(80);
      expect(errors.single, isA<StateError>());
      expect(api.scans, 0);
    },
  );

  test('nunca há duas varreduras ao mesmo tempo', () async {
    final api = FakeMdnsApi([
      [found('A')],
    ])..scanTime = const Duration(milliseconds: 70);
    await listen(make(api));
    await wait(300);
    expect(api.maxConcurrent, 1);
    expect(api.scans, greaterThanOrEqualTo(2));
  });

  test('cancelar para o cliente e as varreduras', () async {
    final api = FakeMdnsApi([
      [found('A')],
    ]);
    await listen(make(api));
    await wait(50);
    await sub.cancel();
    final scans = api.scans;
    await wait(100);
    expect(api.stops, 1);
    expect(api.scans, scans);
  });
}
