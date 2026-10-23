/// Tipo de serviço mDNS que o gateway do Plany anuncia (`_plany._tcp`).
const plannyServiceType = '_plany._tcp';

/// Servidor Plany encontrado na rede local.
class DiscoveredServer {
  const DiscoveredServer({
    required this.name,
    required this.host,
    required this.addresses,
    required this.port,
  });

  /// Nome do serviço: o `SERVER_NAME` configurado no servidor.
  final String name;

  /// Nome mDNS da máquina (sem o `.local`).
  final String host;

  /// Endereços IPv4 do servidor, os que valem para conectar.
  final List<String> addresses;

  final int port;

  /// Onde conectar: o primeiro IPv4 utilizável; sem IP, o nome mDNS da máquina.
  String get address {
    if (addresses.isNotEmpty) return addresses.first;
    return host.isEmpty ? '' : '$host.local';
  }

  /// Endereço base da API deste servidor.
  Uri get baseUri => Uri(scheme: 'http', host: address, port: port);

  @override
  bool operator ==(Object other) =>
      other is DiscoveredServer &&
      other.name == name &&
      other.host == host &&
      other.port == port &&
      _sameList(other.addresses, addresses);

  @override
  int get hashCode => Object.hash(name, host, port, Object.hashAll(addresses));

  @override
  String toString() => 'DiscoveredServer($name, $address:$port)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Um anúncio mDNS é anônimo: qualquer aparelho da rede pode anunciar qualquer
/// endereço. Só interessam IPv4 comuns; fora loopback, link-local, "qualquer"
/// e multicast, que não levam a um servidor da rede.
bool isUsableIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255 || p != n.toString()) return false;
    octets.add(n);
  }
  final first = octets[0];
  if (first == 0 || first == 127 || first >= 224) return false;
  if (first == 169 && octets[1] == 254) return false;
  return true;
}

/// Quantos endereços de um mesmo servidor interessam; o resto é descartado.
const maxAddressesPerServer = 8;

/// IPv4 utilizáveis de [ips], sem repetição, em ordem estável e no máximo
/// [maxAddressesPerServer].
List<String> usableIpv4(Iterable<String> ips) =>
    ({...ips.where(isUsableIpv4)}.toList()..sort())
        .take(maxAddressesPerServer)
        .toList();
