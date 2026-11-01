import 'dart:async';

import 'package:nsd/nsd.dart' as nsd;

import 'discovered_server.dart';
import 'restart_policy.dart';
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
/// server is lost), the search is restarted, each wait twice the previous one
/// ([RestartPolicy]). Stopping a search emits no "lost" and a new one reports every
/// server again as "found", so a restart never makes a known server blink.
/// A "lost" server stays in the list for [lostGrace]; if it is found again
/// within that time, nothing changes for the user (see [ServerTable]).
///
/// The search stops when the subscription is paused (the app went to the background)
/// and starts again on resume, with the servers it knew marked as lost until they answer.
class NsdDiscovery implements ServerDiscovery {
  NsdDiscovery({
    this.api = const PluginNsdApi(),
    this.serviceType = plannyServiceType,
    this.restartWhileEmpty = const Duration(seconds: 15),
    this.maxRestartDelay = const Duration(minutes: 5),
    this.lostGrace = ServerTable.defaultLostGrace,
  });

  final NsdApi api;
  final String serviceType;

  /// The first wait before restarting; it doubles up to [maxRestartDelay].
  final Duration restartWhileEmpty;
  final Duration maxRestartDelay;
  final Duration lostGrace;

  @override
  Stream<List<DiscoveredServer>> watch() {
    final table = ServerTable();
    final policy = RestartPolicy(base: restartWhileEmpty, max: maxRestartDelay);
    final controller = StreamController<List<DiscoveredServer>>();
    Object? session;
    Timer? restartTimer;
    Timer? expireTimer;
    var closed = false;
    var paused = false;
    var working = false;
    // begin, arm and the listener call each other, so the listener is assigned below
    late final void Function(nsd.ServiceStatus, nsd.Service) onService;

    void emit() {
      if (!closed) controller.add(table.snapshot);
    }

    bool healthy() => session != null && !table.isEmpty && !table.hasLost;

    Future<void> begin({required bool initial}) async {
      try {
        final s = await api.startDiscovery(serviceType, onService);
        if (closed || paused) {
          await api.stopDiscovery(s);
        } else {
          session = s;
          policy.succeeded();
        }
      } catch (error, stack) {
        if (!closed && policy.failed(surfaceNow: initial)) {
          controller.addError(error, stack);
        }
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

    void arm() {
      if (closed || paused || restartTimer?.isActive == true || healthy()) {
        return;
      }
      restartTimer = Timer(policy.delay, () async {
        if (closed || paused || working || healthy()) return;
        working = true;
        await end();
        if (!closed && !paused) await begin(initial: false);
        working = false;
        policy.restarted();
        arm();
      });
    }

    void scheduleExpiry() {
      if (closed || paused || expireTimer?.isActive == true || !table.hasLost) {
        return;
      }
      expireTimer = Timer(lostGrace ~/ 3, () {
        if (closed || paused) return;
        if (table.expire(lostGrace)) emit();
        scheduleExpiry();
        arm();
      });
    }

    onService = (nsd.ServiceStatus status, nsd.Service service) {
      final name = service.name;
      if (name == null || name.isEmpty) return;
      var changed = false;
      switch (status) {
        case nsd.ServiceStatus.found:
          final server = _toServer(service);
          if (server != null) {
            changed = table.upsert(server);
            policy.reset();
          }
        case nsd.ServiceStatus.lost:
          // does not leave right away: it may just be an announcement lost on Wi-Fi
          table.markLost(name);
      }
      if (changed) emit();
      scheduleExpiry();
      arm();
    };

    // one start in flight at a time: a resume that comes meanwhile would open a second search and the first
    // one would never be stopped; the one in flight looks at the state when it ends
    Future<void> start({required bool initial}) async {
      if (working) return;
      working = true;
      await begin(initial: initial);
      working = false;
      arm();
    }

    controller.onListen = () {
      emit();
      unawaited(start(initial: true));
      arm();
    };
    controller.onPause = () {
      paused = true;
      restartTimer?.cancel();
      expireTimer?.cancel();
      unawaited(end());
    };
    controller.onResume = () {
      paused = false;
      // the network may have changed while away: what was known must answer again
      policy.reset();
      for (final server in table.snapshot) {
        table.markLost(server.name);
      }
      scheduleExpiry();
      unawaited(start(initial: false));
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
