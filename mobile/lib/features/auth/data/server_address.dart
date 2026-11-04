import 'dart:io';

/// What a person types to add a server: `[http(s)://]host[:port]`, nothing else (no user info, path, query or spaces).
/// Returns where to reach it, or `null` when it is not exactly an address. Without a scheme it is HTTP (the gateway's own
/// port); an explicit `https://` is taken as the secure port itself.
Uri? parseServerAddress(String input) {
  final text = input.trim();
  if (text.isEmpty || text.length > 300 || RegExp(r'\s').hasMatch(text)) return null;
  final m = RegExp(r'^(?:(https?)://)?(\[[0-9a-fA-F:.]+\]|[^/:?#@\[\]]+)(?::(\d{1,5}))?/?$', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  final scheme = (m.group(1) ?? 'http').toLowerCase();
  var host = m.group(2)!.toLowerCase();
  final portText = m.group(3);
  final port = portText == null ? (scheme == 'https' ? 443 : 80) : int.parse(portText);
  if (port < 1 || port > 65535) return null;
  if (host.startsWith('[')) {
    host = host.substring(1, host.length - 1);
    if (InternetAddress.tryParse(host)?.type != InternetAddressType.IPv6) return null;
  } else {
    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (ip.type != InternetAddressType.IPv4) return null;
    } else {
      // "999.1.1.1" and "1.2.3" are not names
      if (RegExp(r'^[0-9.]+$').hasMatch(host)) return null;
      if (host.length > 253 || !RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$').hasMatch(host)) return null;
    }
  }
  return Uri(scheme: scheme, host: host, port: port);
}
