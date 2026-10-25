import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import 'discovered_server.dart';
import 'server_discovery.dart';
import 'server_table.dart';

/// What an mDNS sweep returns for each server.
class MdnsFound {
  const MdnsFound({
    required this.name,
    required this.host,
    required this.port,
    required this.addresses,
    this.id = '',
  });

  final String name;
  final String host;
  final int port;
  final List<String> addresses;

  /// The `id` of the TXT record, when valid.
  final String id;
}

/// The little we use of `multicast_dns`, so it can be swapped out in tests.
abstract interface class MdnsApi {
  Future<void> start();

  /// One sweep: asks who announces [serviceType] and waits up to [timeout].
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
    final txt = await _first(
      _client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(instance),
        timeout: timeout,
      ),
    );
    // "Plany._plany._tcp.local" -> "Plany"
    final name = instance.endsWith('.$domain')
        ? instance.substring(0, instance.length - domain.length - 1)
        : instance;
    return MdnsFound(
      name: name,
      host: _withoutLocal(srv.target),
      port: srv.port,
      addresses: addresses,
      id: txt == null ? '' : serverIdFromTxtText(txt.text),
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

/// Discovery through mDNS sweeps made by the app itself (`multicast_dns`).
/// It is the Linux path, where the `nsd` plugin does not exist. It follows the same rules
/// as `NsdDiscovery`:
///
/// * a server that disappears from a sweep is only marked as lost and stays in the
///   list for [lostGrace]; if it comes back within that time, nothing changes (on Wi-Fi a
///   lost reply is common and does not mean the server left);
/// * while nothing has been found (or some server is lost), the mDNS client
///   is restarted every [restartWhileEmpty], the way nsd restarts the search;
/// * the table has a cap and refuses absurd names ([ServerTable]).
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
              id: isValidServerId(f.id) ? f.id : '',
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
