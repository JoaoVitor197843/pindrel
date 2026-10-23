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
/// cada vez mais espaçadas; por isso, enquanto nada foi achado (ou algum
/// servidor está perdido), a busca é reiniciada a cada [restartWhileEmpty].
/// Um servidor "perdido" segue na lista por [lostGrace]; se for achado de novo
/// nesse prazo, nada muda para o usuário (ver [ServerTable]).
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
          // não sai na hora: pode ser só um anúncio perdido no Wi-Fi
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
        // parar uma busca que já caiu não é um erro que o usuário possa tratar
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
    );
  }
}

String _hostWithoutLocal(String host) {
  var h = host;
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h.endsWith('.local')) h = h.substring(0, h.length - '.local'.length);
  return h;
}
