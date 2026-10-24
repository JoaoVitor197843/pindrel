import 'package:http/http.dart' as http;

/// Does the server at [baseUri] respond? Any HTTP response (even an error) counts:
/// all that matters is that someone is on the other end.
typedef ServerProbe = Future<bool> Function(Uri baseUri);

const probeTimeout = Duration(seconds: 3);

/// Queries the server's `/server/info/`, waiting up to [probeTimeout].
Future<bool> httpServerProbe(Uri baseUri, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    await c.get(baseUri.resolve('/server/info/')).timeout(probeTimeout);
    return true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) c.close();
  }
}
