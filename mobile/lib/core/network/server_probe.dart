import 'package:http/http.dart' as http;

/// O servidor em [baseUri] responde? Qualquer resposta HTTP (até um erro) vale:
/// o que interessa é haver alguém do outro lado.
typedef ServerProbe = Future<bool> Function(Uri baseUri);

const probeTimeout = Duration(seconds: 3);

/// Consulta `/server/info/` do servidor, com [probeTimeout] de espera.
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
