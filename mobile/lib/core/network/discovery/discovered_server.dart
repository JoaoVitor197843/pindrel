import 'dart:convert';
import 'dart:typed_data';

/// mDNS service type that the Pindrel gateway announces (`_pindrel._tcp`).
const plannyServiceType = '_pindrel._tcp';

/// Pindrel server found on the local network.
class DiscoveredServer {
  const DiscoveredServer({
    required this.name,
    required this.host,
    required this.addresses,
    required this.port,
    this.id = '',
  });

  /// Service name: the `SERVER_NAME` configured on the server.
  final String name;

  /// The machine's mDNS name (without the `.local`).
  final String host;

  /// The server's IPv4 addresses, the ones worth connecting to.
  final List<String> addresses;

  final int port;

  /// The random id the server keeps (`id` in the TXT record); empty when it announces none (an older server)
  /// or announces something that is not an id.
  final String id;

  /// Where to connect: the first usable IPv4; with no IP, the machine's mDNS name.
  String get address {
    if (addresses.isNotEmpty) return addresses.first;
    return host.isEmpty ? '' : '$host.local';
  }

  Uri get baseUri => Uri(scheme: 'http', host: address, port: port);

  @override
  bool operator ==(Object other) =>
      other is DiscoveredServer &&
      other.name == name &&
      other.host == host &&
      other.port == port &&
      other.id == id &&
      _sameList(other.addresses, addresses);

  @override
  int get hashCode =>
      Object.hash(name, host, port, id, Object.hashAll(addresses));

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

/// An mDNS announcement is anonymous: any device on the network can announce any
/// address. Only ordinary IPv4 matters; loopback, link-local, "any"
/// and multicast are out, since they do not lead to a server on the network.
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

/// How many addresses of the same server matter; the rest are discarded.
const maxAddressesPerServer = 8;

/// Usable IPv4 addresses from [ips], without repeats, in a stable order and at most
/// [maxAddressesPerServer].
List<String> usableIpv4(Iterable<String> ips) => ({
  ...ips.where(isUsableIpv4),
}.toList()..sort()).take(maxAddressesPerServer).toList();

/// An id is what a server chose for itself and then travels over the network: only plain, short text counts.
bool isValidServerId(String id) => RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(id);

/// The `id` of a TXT record as the `nsd` plugin delivers it (values are raw bytes); empty when absent or unusable.
String serverIdFromTxt(Map<String, Uint8List?>? txt) {
  final raw = txt?['id'];
  if (raw == null || raw.length > 64) return '';
  try {
    final id = utf8.decode(raw);
    return isValidServerId(id) ? id : '';
  } catch (_) {
    return '';
  }
}

/// The `id` of a TXT record as `multicast_dns` delivers it (`key=value` entries, one per line).
String serverIdFromTxtText(String text) {
  for (final entry in text.split('\n')) {
    if (entry.startsWith('id=')) {
      final id = entry.substring(3);
      return isValidServerId(id) ? id : '';
    }
  }
  return '';
}
