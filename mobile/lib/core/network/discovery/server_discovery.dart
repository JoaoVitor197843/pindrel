import 'discovered_server.dart';

/// Procura servidores Plany na rede local.
abstract interface class ServerDiscovery {
  /// Emite a lista completa dos servidores conhecidos a cada mudança (a
  /// primeira, vazia, já na assinatura). A busca começa ao assinar e termina ao
  /// cancelar. Um erro (por exemplo, sem permissão de rede) sai como erro do
  /// stream.
  Stream<List<DiscoveredServer>> watch();
}

/// Para plataformas sem mDNS (web): nunca acha nada.
class NoDiscovery implements ServerDiscovery {
  const NoDiscovery();

  @override
  Stream<List<DiscoveredServer>> watch() =>
      Stream.value(const <DiscoveredServer>[]);
}
