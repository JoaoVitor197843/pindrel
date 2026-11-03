import 'package:http/http.dart' as http;

import 'pairing.dart';

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

/// The address could not be taken for a Pindrel server: nothing answered, or what answered is not one.
class ServerLookupFailed implements Exception {
  const ServerLookupFailed(this.reason);

  /// `unreachable` or `notPindrel`.
  final PairingFailure reason;

  @override
  String toString() => 'ServerLookupFailed($reason)';
}

/// The TLS port [base] offers, or `null` when it is a Pindrel server that offers none. Throws [ServerLookupFailed] when nothing
/// answers ([PairingFailure.unreachable]) or when what answers is not a Pindrel server ([PairingFailure.notPindrel]): a Pindrel
/// gateway always says its id on `/server/info/`, so a page without one (a site, another program) is not one.
Future<TlsOffer?> fetchTlsOffer(Uri base, {http.Client? client, Duration timeout = offerTimeout}) async {
  final c = client ?? http.Client();
  try {
    final http.Response r;
    try {
      r = await c.get(base.resolve('/server/info/')).timeout(timeout);
    } catch (_) {
      throw const ServerLookupFailed(PairingFailure.unreachable);
    }
    final id = r.headers[idHeader] ?? '';
    if (r.statusCode != 200 || !_idShape.hasMatch(id)) throw const ServerLookupFailed(PairingFailure.notPindrel);
    final port = int.tryParse(r.headers[tlsHeader] ?? '');
    if (port == null || port < 1 || port > 65535) return null;
    return TlsOffer(port: port, serverId: id);
  } finally {
    if (client == null) c.close();
  }
}
