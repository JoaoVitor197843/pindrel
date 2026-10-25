import '../../../core/network/discovery/discovered_server.dart';

/// Plany server the app can connect to.
class ServerOption {
  const ServerOption({
    required this.id,
    required this.name,
    required this.address,
    this.baseUri,
    this.serverId = '',
  });

  /// From a server found on the network.
  factory ServerOption.fromDiscovered(DiscoveredServer server) => ServerOption(
    id: idFor(server.name),
    name: server.name,
    address: '${server.address}:${server.port}',
    baseUri: server.baseUri,
    serverId: server.id,
  );

  final String id;
  final String name;

  /// How the address appears on screen (`192.168.1.116:8095`).
  final String address;

  /// Where the API responds, when the server came from the network.
  final Uri? baseUri;

  /// The id the server announced for itself (empty: it announces none). Two servers with the same name but
  /// another id are not the same server.
  final String serverId;

  /// Stable identifier derived from the name: lowercase, without accents and only with
  /// letters, numbers and hyphens.
  static String idFor(String name) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final plain = name.toLowerCase().split('').map((c) {
      final i = from.indexOf(c);
      return i < 0 ? c : to[i];
    }).join();
    final slug = plain
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'servidor' : slug;
  }

  @override
  bool operator ==(Object other) =>
      other is ServerOption && other.id == id && other.serverId == serverId;

  @override
  int get hashCode => Object.hash(id, serverId);
}
