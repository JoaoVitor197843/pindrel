/// Servidor Plany ao qual o app pode se conectar.
class ServerOption {
  const ServerOption({
    required this.id,
    required this.name,
    required this.address,
  });

  final String id;
  final String name;
  final String address;

  @override
  bool operator ==(Object other) => other is ServerOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
