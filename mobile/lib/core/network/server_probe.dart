import 'dart:async';

import 'package:http/http.dart' as http;

/// Does the server at [baseUri] respond? Any HTTP response (even an error) counts:
/// all that matters is that someone is on the other end.
typedef ServerProbe = Future<bool> Function(Uri baseUri);

const probeTimeout = Duration(seconds: 3);

/// GETs [uri] and keeps only the status and the headers: the body is dropped unread. What answers on the network is not
/// trusted, and `client.get` would hold a body of any size in memory until the timeout.
Future<http.BaseResponse> headersOf(http.Client client, Uri uri, Duration timeout) async {
  final response = await client.send(http.Request('GET', uri)).timeout(timeout);
  unawaited(response.stream.listen(null).cancel().then((_) {}, onError: (Object _) {}));
  return response;
}

/// Queries the server's `/server/info/`, waiting up to [probeTimeout].
Future<bool> httpServerProbe(Uri baseUri, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    await headersOf(c, baseUri.resolve('/server/info/'), probeTimeout);
    return true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) c.close();
  }
}
