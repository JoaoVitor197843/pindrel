import 'dart:async';

import 'package:nsd/nsd.dart' as nsd;

import 'discovered_server.dart';
import 'server_discovery.dart';
import 'server_table.dart';

/// The little we use of the `nsd` plugin, so it can be swapped out in tests.
abstract interface class NsdApi {
  /// Starts looking for [serviceType]. [listener] receives each service found
  /// (already resolved, with addresses) or lost. Returns the session, so it can be stopped.
  Future<Object> startDiscovery(
    String serviceType,
    void Function(nsd.ServiceStatus status, nsd.Service service) listener,
  );

  Future<void> stopDiscovery(Object session);
}

class PluginNsdApi implements NsdApi {
  const PluginNsdApi();

  @override
  Future<Object> startDiscovery(
    String serviceType,
    void Function(nsd.ServiceStatus status, nsd.Service service) listener,
  ) async {
    final discovery = await nsd.startDiscovery(
      serviceType,
      autoResolve: true,
      ipLookupType: nsd.IpLookupType.v4,
    );
    discovery.addServiceListener(
      (service, status) => listener(status, service),
    );
    return discovery;
  }

  @override
  Future<void> stopDiscovery(Object session) =>
      nsd.stopDiscovery(session as nsd.Discovery);
}

/// Discovery through each system's native service (NsdManager on Android,
/// Bonjour on iOS and macOS, DNS-SD on Windows), via the `nsd` plugin.
///
/// Wi-Fi drops many multicast packets and the system's retries get
/// further and further apart; so, while nothing has been found (or some
/// server is lost), the search is restarted every [restartWhileEmpty].
/// A "lost" server stays in the list for [lostGrace]; if it is found again
/// within that time, nothing changes for the user (see [ServerTable]).
class NsdDiscovery implements ServerDiscovery {
  NsdDiscovery({
    this.api = const PluginNsdApi(),
    this.serviceType = plannyServiceType,
    this.restartWhileEmpty = const Duration(seconds: 15),
    this.lostGrace = ServerTable.defaultLostGrace,
  });

  final NsdApi api;
  final String serviceType;
  final Duration restartWhileEmpty;
  final Duration lostGrace;

  @override
  Stream<List<DiscoveredServer>> watch() {
    final table = ServerTable();
    final controller = StreamController<List<DiscoveredServer>>();
    Object? session;
    Timer? restartTimer;
    Timer? expireTimer;
    var closed = false;
    var restarting = false;

    void emit() {
      if (!closed) controller.add(table.snapshot);
    }

    void scheduleExpiry() {
      if (closed || expireTimer?.isActive == true || !table.hasLost) return;
      expireTimer = Timer(lostGrace ~/ 3, () {
        if (closed) return;
        if (table.expire(lostGrace)) emit();
        scheduleExpiry();
      });
    }

    void onService(nsd.ServiceStatus status, nsd.Service service) {
      final name = service.name;
      if (name == null || name.isEmpty) return;
      var changed = false;
      switch (status) {
        case nsd.ServiceStatus.found:
          final server = _toServer(service);
          if (server != null) changed = table.upsert(server);
        case nsd.ServiceStatus.lost:
          // does not leave right away: it may just be an announcement lost on Wi-Fi
          table.markLost(name);
      }
      if (changed) emit();
      scheduleExpiry();
    }

    Future<void> begin() async {
      try {
        final s = await api.startDiscovery(serviceType, onService);
        if (closed) {
          await api.stopDiscovery(s);
        } else {
          session = s;
        }
      } catch (error, stack) {
        if (!closed) controller.addError(error, stack);
      }
    }

    Future<void> end() async {
      final s = session;
      session = null;
      if (s == null) return;
      try {
        await api.stopDiscovery(s);
      } catch (_) {
        // stopping a search that has already dropped is not an error the user can handle
      }
    }

    controller.onListen = () {
      emit();
      begin();
      restartTimer = Timer.periodic(restartWhileEmpty, (_) async {
        if (closed || restarting) return;
        if (!table.isEmpty && !table.hasLost) return;
        restarting = true;
        await end();
        if (!closed) await begin();
        restarting = false;
      });
    };
    controller.onCancel = () async {
      closed = true;
      restartTimer?.cancel();
      expireTimer?.cancel();
      await end();
    };
    return controller.stream;
  }

  DiscoveredServer? _toServer(nsd.Service service) {
    final port = service.port;
    if (port == null || port <= 0 || port > 65535) return null;
    return DiscoveredServer(
      name: service.name!,
      host: _hostWithoutLocal(service.host ?? ''),
      addresses: usableIpv4(
        (service.addresses ?? const []).map((a) => a.address),
      ),
      port: port,
      id: serverIdFromTxt(service.txt),
    );
  }
}

String _hostWithoutLocal(String host) {
  var h = host;
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h.endsWith('.local')) h = h.substring(0, h.length - '.local'.length);
  return h;
}
