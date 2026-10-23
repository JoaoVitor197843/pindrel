import 'dart:async';

import 'package:nsd/nsd.dart' as nsd;

import 'discovered_server.dart';
import 'server_discovery.dart';
import 'server_table.dart';

/// O pouco que usamos do plugin `nsd`, para poder trocá-lo nos testes.
abstract interface class NsdApi {
  /// Começa a procurar [serviceType]. [listener] recebe cada serviço achado
  /// (já resolvido, com endereços) ou perdido. Devolve a sessão, para parar.
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

/// Descoberta pelo serviço nativo de cada sistema (NsdManager no Android,
/// Bonjour no iOS e macOS, DNS-SD no Windows), via plugin `nsd`.
///
/// O Wi-Fi perde muitos pacotes multicast e as retentativas do sistema ficam
/// cada vez mais espaçadas; por isso, enquanto nada foi achado, a busca é
/// reiniciada a cada [restartWhileEmpty].
class NsdDiscovery implements ServerDiscovery {
  NsdDiscovery({
    this.api = const PluginNsdApi(),
    this.serviceType = plannyServiceType,
    this.restartWhileEmpty = const Duration(seconds: 15),
  });

  final NsdApi api;
  final String serviceType;
  final Duration restartWhileEmpty;

  @override
  Stream<List<DiscoveredServer>> watch() {
    final table = ServerTable();
    final controller = StreamController<List<DiscoveredServer>>();
    Object? session;
    Timer? restartTimer;
    var closed = false;
    var restarting = false;

    void emit() {
      if (!closed) controller.add(table.snapshot);
    }

    void onService(nsd.ServiceStatus status, nsd.Service service) {
      final name = service.name;
      if (name == null || name.isEmpty) return;
      final changed = switch (status) {
        nsd.ServiceStatus.found => switch (_toServer(service)) {
          final server? => table.upsert(server),
          null => false,
        },
        nsd.ServiceStatus.lost => table.remove(name),
      };
      if (changed) emit();
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
        // parar uma busca que já caiu não é um erro que o usuário possa tratar
      }
    }

    controller.onListen = () {
      emit();
      begin();
      restartTimer = Timer.periodic(restartWhileEmpty, (_) async {
        if (closed || restarting || !table.isEmpty) return;
        restarting = true;
        await end();
        if (!closed) await begin();
        restarting = false;
      });
    };
    controller.onCancel = () async {
      closed = true;
      restartTimer?.cancel();
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
    );
  }
}

String _hostWithoutLocal(String host) {
  var h = host;
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h.endsWith('.local')) h = h.substring(0, h.length - '.local'.length);
  return h;
}
