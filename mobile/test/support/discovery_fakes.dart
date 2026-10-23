import 'dart:async';
import 'dart:math';

import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/server_discovery.dart';

/// Uma descoberta controlada pelo teste: começa com [initial] e [emit] troca a lista.
class FakeDiscovery implements ServerDiscovery {
  FakeDiscovery([List<DiscoveredServer> initial = const []])
    : _current = initial;

  List<DiscoveredServer> _current;
  final _updates = StreamController<List<DiscoveredServer>>.broadcast();
  int listeners = 0;

  void emit(List<DiscoveredServer> servers) {
    _current = servers;
    _updates.add(servers);
  }

  /// A busca falha, como acontece sem permissão de rede.
  void fail(Object error) => _updates.addError(error);

  @override
  Stream<List<DiscoveredServer>> watch() => Stream.multi((controller) {
    listeners++;
    controller.add(_current);
    final sub = _updates.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = () {
      listeners--;
      return sub.cancel();
    };
  });
}

/// Sorteio previsível: sempre devolve [value] (limitado ao máximo pedido).
class FixedRandom implements Random {
  FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

DiscoveredServer server(
  String name, {
  String host = '',
  List<String> addresses = const [],
  int port = 8080,
}) =>
    DiscoveredServer(name: name, host: host, addresses: addresses, port: port);

/// Os três servidores que a tela de login mostrava antes da descoberta real.
final sampleServers = [
  server('Casa', host: 'plany.casa'),
  server('Escritório', addresses: ['192.168.0.20']),
  server('Nuvem', host: 'notas.exemplo'),
];
