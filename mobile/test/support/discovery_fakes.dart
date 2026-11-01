import 'dart:async';
import 'dart:math';

import 'package:mobile/core/network/discovery/discovered_server.dart';
import 'package:mobile/core/network/discovery/server_discovery.dart';

/// A discovery controlled by the test: starts with [initial] and [emit] swaps the list.
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

  /// The search fails, as happens without network permission.
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

/// A discovery that honours pause and resume of the subscription, like the real ones.
class PausableDiscovery implements ServerDiscovery {
  PausableDiscovery(this.initial);

  final List<DiscoveredServer> initial;
  int pauses = 0;
  int resumes = 0;
  late final StreamController<List<DiscoveredServer>> out;

  @override
  Stream<List<DiscoveredServer>> watch() {
    out = StreamController<List<DiscoveredServer>>(
      onPause: () => pauses++,
      onResume: () => resumes++,
    );
    out.add(initial);
    return out.stream;
  }
}

/// Predictable draw: always returns [value] (capped at the requested maximum).
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
  String id = '',
}) => DiscoveredServer(
  name: name,
  host: host,
  addresses: addresses,
  port: port,
  id: id,
);

/// The three servers the login screen showed before the real discovery.
final sampleServers = [
  server('Casa', host: 'plany.casa'),
  server('Escritório', addresses: ['192.168.0.20']),
  server('Nuvem', host: 'notas.exemplo'),
];
