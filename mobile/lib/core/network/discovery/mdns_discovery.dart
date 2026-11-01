import 'dart:async';
import 'dart:io';

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

/// How many times each question of a sweep is asked before giving up on it.
const _asks = 3;

/// The mDNS multicast group (IPv4).
final _mdnsGroup = InternetAddress('224.0.0.251');

/// The interfaces on which the mDNS group can be joined. `MDnsClient` joins it on every
/// interface and a single refusal aborts the whole start; virtual adapters such as Tailscale's
/// refuse on Windows (WSAENOPROTOOPT, 10042), so the search never started. Interfaces that
/// refuse are left out; if none accepts, all are returned so the real error still shows.
Future<Iterable<NetworkInterface>> _interfacesThatJoinMdns(
  InternetAddressType type,
) async {
  final all = await NetworkInterface.list(
    includeLinkLocal: true,
    type: type,
    includeLoopback: false,
  );
  if (type != InternetAddressType.IPv4) return all;
  final joinable = <NetworkInterface>[];
  for (final interface in all) {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.joinMulticast(_mdnsGroup, interface);
      joinable.add(interface);
    } on OSError {
      // this interface does not do multicast (`joinMulticast` throws the raw OSError)
    } on SocketException {
      // same, or the probe socket could not be opened
    } finally {
      socket?.close();
    }
  }
  return joinable.isEmpty ? all : joinable;
}

/// The little we use of `multicast_dns`, so it can be swapped out in tests.
abstract interface class MdnsApi {
  Future<void> start();

  /// One sweep: asks who announces [serviceType] and waits up to [timeout].
  Future<List<MdnsFound>> scan(String serviceType, Duration timeout);

  void stop();
}

/// `IP_MULTICAST_IF` on Windows: which interface multicast packets leave through.
const _windowsIpMulticastIf = 9;

/// The address of the local network (private IPv4; not Tailscale's 100.64/10 nor link-local)
/// among [interfaces], or null.
InternetAddress? _lanAddress(Iterable<NetworkInterface> interfaces) {
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      final b = address.rawAddress;
      if (address.type != InternetAddressType.IPv4) continue;
      if (b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168)) {
        return address;
      }
    }
  }
  return null;
}

class PluginMdnsApi implements MdnsApi {
  MDnsClient _client = MDnsClient();

  /// On Windows an mDNS question leaves through whichever interface the system finds
  /// first (often a VPN's), where nobody answers: with the default, no question of ours
  /// got an answer; sent through the Wi-Fi, nearly all did. So the sending socket is told
  /// which interface to use (the local network's); the replies are heard on all of them.
  @override
  Future<void> start() async {
    final interfaces = (await _interfacesThatJoinMdns(
      InternetAddressType.IPv4,
    )).toList();
    final lan = Platform.isWindows ? _lanAddress(interfaces) : null;
    _client = MDnsClient(
      rawDatagramSocketFactory:
          (
            dynamic host,
            int port, {
            bool reuseAddress = true,
            bool reusePort = true,
            int ttl = 1,
          }) async {
            final socket = await RawDatagramSocket.bind(
              host,
              port,
              reuseAddress: reuseAddress,
              reusePort: reusePort && !Platform.isWindows,
              ttl: ttl,
            );
            if (lan != null) {
              socket.setRawOption(
                RawSocketOption(
                  RawSocketOption.levelIPv4,
                  _windowsIpMulticastIf,
                  lan.rawAddress,
                ),
              );
            }
            return socket;
          },
    );
    await _client.start(interfacesFactory: (_) async => interfaces);
  }

  @override
  void stop() => _client.stop();

  @override
  Future<List<MdnsFound>> scan(String serviceType, Duration timeout) async {
    final domain = '$serviceType.local';
    final instances = <String>{
      for (final ptr in await _ask<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(domain),
        timeout,
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
    final srv = (await _ask<SrvResourceRecord>(
      ResourceRecordQuery.service(instance),
      timeout,
    )).firstOrNull;
    if (srv == null) return null;
    final addresses = [
      for (final a in await _ask<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(srv.target),
        timeout,
      ))
        a.address.address,
    ];
    final txt = (await _ask<TxtResourceRecord>(
      ResourceRecordQuery.text(instance),
      timeout,
    )).firstOrNull;
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

  /// Asks for [query] up to [_asks] times, splitting [timeout] between the asks, and
  /// stops at the first one that gets an answer. Wi-Fi drops multicast packets and a
  /// single `lookup` asks only once; replies to one ask also carry the other records
  /// of the service, which the client caches and which answer the next lookups at once.
  Future<List<T>> _ask<T extends ResourceRecord>(
    ResourceRecordQuery query,
    Duration timeout,
  ) async {
    final slice = timeout ~/ _asks;
    for (var ask = 0; ask < _asks; ask++) {
      final found = [
        await for (final record in _client.lookup<T>(query, timeout: slice))
          record,
      ];
      if (found.isNotEmpty) return found;
    }
    return const [];
  }
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

    var starting = false;

    /// Brings the client up and starts the sweeps. Only one start is in flight at a time: a pause or a resume that
    /// comes meanwhile does not start another, the one in flight looks at the state when it ends (otherwise two clients
    /// and two timers would come up, and a pause would leave the client running).
    Future<void> startSearch({required bool initial}) async {
      if (starting) return;
      starting = true;
      final up = await startClient(initial: initial);
      starting = false;
      started = true;
      if (closed || paused) {
        if (up) {
          _api.stop();
          clientUp = false;
        }
        return;
      }
      timer?.cancel();
      if (up) unawaited(scanOnce());
      // without the client the sweeps still go on: each one tries it again, with the usual wait
      timer = Timer.periodic(interval, (_) => scanOnce());
    }

    controller.onListen = () async {
      emit();
      await startSearch(initial: true);
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
      await startSearch(initial: false);
    };
    controller.onCancel = () {
      closed = true;
      timer?.cancel();
      if (clientUp) _api.stop();
    };
    return controller.stream;
  }
}
