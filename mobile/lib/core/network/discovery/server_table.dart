import 'discovered_server.dart';

/// Os servidores conhecidos agora, por nome (o nome do serviço é único na rede:
/// o mDNS renomeia em caso de conflito).
class ServerTable {
  final Map<String, DiscoveredServer> _byName = {};

  bool get isEmpty => _byName.isEmpty;

  /// Insere ou substitui (um servidor reanunciado traz o endereço mais novo).
  /// Devolve se algo mudou.
  bool upsert(DiscoveredServer server) {
    if (_byName[server.name] == server) return false;
    _byName[server.name] = server;
    return true;
  }

  /// Devolve se havia o servidor.
  bool remove(String name) => _byName.remove(name) != null;

  /// Lista imutável, ordenada por nome (sem diferenciar maiúsculas).
  List<DiscoveredServer> get snapshot => List.unmodifiable(
    _byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );
}
