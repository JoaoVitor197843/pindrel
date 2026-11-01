import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import 'discovered_server.dart';
import 'restart_policy.dart';
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
///   is restarted with a wait that doubles each time ([RestartPolicy]);
/// * the table has a cap and refuses absurd names ([ServerTable]);
/// * a paused subscription stops the client and the sweeps; resuming starts them again
///   with the known servers marked as lost until they answer.
class MdnsDiscovery implements ServerDiscovery {
  MdnsDiscovery({
    MdnsApi? api,
    this.serviceType = plannyServiceType,
    this.interval = const Duration(seconds: 5),
    this.scanTimeout = const Duration(seconds: 3),
    this.restartWhileEmpty = const Duration(seconds: 15),
    this.maxRestartDelay = const Duration(minutes: 5),
    this.lostGrace = ServerTable.defaultLostGrace,
  }) : _api = api ?? PluginMdnsApi();

  final MdnsApi _api;
  final String serviceType;
  final Duration interval;
  final Duration scanTimeout;

  /// The first wait before restarting the client; it doubles up to [maxRestartDelay].
  final Duration restartWhileEmpty;
  final Duration maxRestartDelay;
  final Duration lostGrace;

  @override
  Stream<List<DiscoveredServer>> watch() {
    final table = ServerTable();
    final policy = RestartPolicy(base: restartWhileEmpty, max: maxRestartDelay);
    final controller = StreamController<List<DiscoveredServer>>();
    Timer? timer;
    var closed = false;
    var paused = false;
    var scanning = false;
    var started = false;
    var clientUp = false;
    var lastStart = DateTime.now();

    void emit() {
      if (!closed) controller.add(table.snapshot);
    }

    bool healthy() => clientUp && !table.isEmpty && !table.hasLost;

    /// Starts the client (again). A failure is counted; it reaches the user only
    /// when it repeats ([RestartPolicy.failed]), or at once if it is the first start.
    Future<bool> startClient({required bool initial}) async {
      lastStart = DateTime.now();
      try {
        await _api.start();
        clientUp = true;
        policy.succeeded();
        return true;
      } catch (error, stack) {
        clientUp = false;
        if (!closed && policy.failed(surfaceNow: initial)) {
          controller.addError(error, stack);
        }
        return false;
      }
    }

    Future<void> restartIfDue() async {
      if (healthy()) return;
      if (DateTime.now().difference(lastStart) < policy.delay) return;
      if (clientUp) _api.stop();
      clientUp = false;
      policy.restarted();
      await startClient(initial: false);
    }

    Future<void> scanOnce() async {
      if (closed || paused || scanning || !started) return;
      scanning = true;
      try {
        await restartIfDue();
        if (!clientUp) return;
        final found = await _api.scan(serviceType, scanTimeout);
        if (closed || paused) return;
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
        if (seen.isNotEmpty) policy.reset();
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
      if (!await startClient(initial: true)) {
        // the sweeps go on: each one tries the client again, with the usual wait
        started = true;
        timer = Timer.periodic(interval, (_) => scanOnce());
        return;
      }
      started = true;
      if (closed) {
        _api.stop();
        return;
      }
      unawaited(scanOnce());
      timer = Timer.periodic(interval, (_) => scanOnce());
    };
    controller.onPause = () {
      paused = true;
      timer?.cancel();
      if (clientUp) _api.stop();
      clientUp = false;
    };
    controller.onResume = () async {
      paused = false;
      policy.reset();
      for (final server in table.snapshot) {
        table.markLost(server.name);
      }
      if (!await startClient(initial: false)) {
        if (!closed && !paused) {
          timer = Timer.periodic(interval, (_) => scanOnce());
        }
        return;
      }
      if (closed || paused) {
        _api.stop();
        clientUp = false;
        return;
      }
      unawaited(scanOnce());
      timer = Timer.periodic(interval, (_) => scanOnce());
    };
    controller.onCancel = () {
      closed = true;
      timer?.cancel();
      if (clientUp) _api.stop();
    };
    return controller.stream;
  }
}
