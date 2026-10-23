import '../../../core/network/discovery/discovered_server.dart';

/// Servidor Plany ao qual o app pode se conectar.
class ServerOption {
  const ServerOption({
    required this.id,
    required this.name,
    required this.address,
    this.baseUri,
  });

  /// A partir de um servidor achado na rede.
  factory ServerOption.fromDiscovered(DiscoveredServer server) => ServerOption(
    id: idFor(server.name),
    name: server.name,
    address: '${server.address}:${server.port}',
    baseUri: server.baseUri,
  );

  final String id;
  final String name;

  /// Como o endereço aparece na tela (`192.168.1.116:8095`).
  final String address;

  /// Onde a API responde, quando o servidor veio da rede.
  final Uri? baseUri;

  /// Identificador estável derivado do nome: minúsculas, sem acentos e só com
  /// letras, números e hífens.
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
  bool operator ==(Object other) => other is ServerOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
