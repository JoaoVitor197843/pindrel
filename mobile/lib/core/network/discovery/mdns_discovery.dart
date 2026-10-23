import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import 'discovered_server.dart';
import 'server_discovery.dart';
import 'server_table.dart';

/// O que uma varredura mDNS devolve para cada servidor.
class MdnsFound {
  const MdnsFound({
    required this.name,
    required this.host,
    required this.port,
    required this.addresses,
  });

  final String name;
  final String host;
  final int port;
  final List<String> addresses;
}

/// O pouco que usamos do `multicast_dns`, para poder trocá-lo nos testes.
abstract interface class MdnsApi {
  Future<void> start();

  /// Uma varredura: pergunta quem anuncia [serviceType] e espera até [timeout].
  Future<List<MdnsFound>> scan(String serviceType, Duration timeout);

  void stop();
}

class PluginMdnsApi implements MdnsApi {
  final MDnsClient _client = MDnsClient();

  @override
  Future<void> start() => _client.start();

  @override
  void stop() => _client.stop();

  @override
  Future<List<MdnsFound>> scan(String serviceType, Duration timeout) async {
    final domain = '$serviceType.local';
    final instances = <String>{
      await for (final ptr in _client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(domain),
        timeout: timeout,
      ))
        ptr.domainName,
    };
    final found = await Future.wait(
      instances.map((instance) => _resolve(instance, domain, timeout)),
    );
    return [for (final f in found) ?f];
  }

  Future<MdnsFound?> _resolve(
    String instance,
    String domain,
    Duration timeout,
  ) async {
    final srv = await _first(
      _client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(instance),
        timeout: timeout,
      ),
    );
    if (srv == null) return null;
    final addresses = [
      await for (final a in _client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(srv.target),
        timeout: timeout,
      ))
        a.address.address,
    ];
    // "Plany._plany._tcp.local" -> "Plany"
    final name = instance.endsWith('.$domain')
        ? instance.substring(0, instance.length - domain.length - 1)
        : instance;
    return MdnsFound(
      name: name,
      host: _withoutLocal(srv.target),
      port: srv.port,
      addresses: addresses,
    );
  }
}

Future<T?> _first<T>(Stream<T> stream) async {
  await for (final value in stream) {
    return value;
  }
  return null;
}

String _withoutLocal(String host) {
  var h = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  if (h.endsWith('.local')) h = h.substring(0, h.length - '.local'.length);
  return h;
}

/// Descoberta por varreduras mDNS feitas pelo próprio app (`multicast_dns`).
/// É o caminho do Linux, onde o plugin `nsd` não existe. Segue as mesmas regras
/// do `NsdDiscovery`:
///
/// * um servidor que some de uma varredura é só marcado como perdido e segue na
///   lista por [lostGrace]; se voltar nesse prazo, nada muda (no Wi-Fi uma
///   resposta perdida é comum e não quer dizer que o servidor foi embora);
/// * enquanto nada foi achado (ou algum servidor está perdido), o cliente mDNS
///   é reiniciado a cada [restartWhileEmpty], como o nsd reinicia a busca;
/// * a tabela tem teto e recusa nomes absurdos ([ServerTable]).
class MdnsDiscovery implements ServerDiscovery {
  MdnsDiscovery({
    MdnsApi? api,
    this.serviceType = plannyServiceType,
    this.interval = const Duration(seconds: 5),
    this.scanTimeout = const Duration(seconds: 3),
    this.restartWhileEmpty = const Duration(seconds: 15),
    this.lostGrace = ServerTable.defaultLostGrace,
  }) : _api = api ?? PluginMdnsApi();

  final MdnsApi _api;
  final String serviceType;
  final Duration interval;
  final Duration scanTimeout;
  final Duration restartWhileEmpty;
  final Duration lostGrace;

  @override
  Stream<List<DiscoveredServer>> watch() {
    final table = ServerTable();
    final controller = StreamController<List<DiscoveredServer>>();
    Timer? timer;
    var closed = false;
    var scanning = false;
    var started = false;
    var lastStart = DateTime.now();

    void emit() {
      if (!closed) controller.add(table.snapshot);
    }

    Future<void> restartIfStuck() async {
      if (!table.isEmpty && !table.hasLost) return;
      if (DateTime.now().difference(lastStart) < restartWhileEmpty) return;
      _api.stop();
      await _api.start();
      lastStart = DateTime.now();
    }

    Future<void> scanOnce() async {
      if (closed || scanning || !started) return;
      scanning = true;
      try {
        await restartIfStuck();
        final found = await _api.scan(serviceType, scanTimeout);
        if (closed) return;
        var changed = false;
        final seen = <String>{};
        for (final f in found) {
          if (f.port <= 0 || f.port > 65535) continue;
          seen.add(f.name);
          changed |= table.upsert(
            DiscoveredServer(
              name: f.name,
              host: f.host,
              addresses: usableIpv4(f.addresses),
              port: f.port,
            ),
          );
        }
        for (final server in table.snapshot) {
          if (!seen.contains(server.name)) table.markLost(server.name);
        }
        changed |= table.expire(lostGrace);
        if (changed) emit();
      } catch (error, stack) {
        if (!closed) controller.addError(error, stack);
      } finally {
        scanning = false;
      }
    }

    controller.onListen = () async {
      emit();
      try {
        await _api.start();
      } catch (error, stack) {
        if (!closed) controller.addError(error, stack);
        return;
      }
      started = true;
      lastStart = DateTime.now();
      if (closed) {
        _api.stop();
        return;
      }
      unawaited(scanOnce());
      timer = Timer.periodic(interval, (_) => scanOnce());
    };
    controller.onCancel = () {
      closed = true;
      timer?.cancel();
      if (started) _api.stop();
    };
    return controller.stream;
  }
}
