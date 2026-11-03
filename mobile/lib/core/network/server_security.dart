import 'package:http/http.dart' as http;

/// What a server says about its secure side on `GET /server/info/` (read over the plain port, so it is only a pointer: the
/// pairing digits are what the person trusts).
class TlsOffer {
  const TlsOffer({required this.port, this.serverId = ''});

  /// Where HTTPS listens.
  final int port;

  /// The id the server announces for itself, empty when it announces none.
  final String serverId;
}

const tlsHeader = 'x-pindrel-tls';
const idHeader = 'x-pindrel-id';
const offerTimeout = Duration(seconds: 3);

final _idShape = RegExp(r'^[0-9A-Za-z-]{1,64}$');

/// The TLS port [base] offers, or `null` when it offers none, does not answer, or answers something that is not a port.
Future<TlsOffer?> fetchTlsOffer(Uri base, {http.Client? client, Duration timeout = offerTimeout}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(base.resolve('/server/info/')).timeout(timeout);
    final port = int.tryParse(r.headers[tlsHeader] ?? '');
    if (port == null || port < 1 || port > 65535) return null;
    final id = r.headers[idHeader] ?? '';
    return TlsOffer(port: port, serverId: _idShape.hasMatch(id) ? id : '');
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
