import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:mobile/core/network/pairing.dart';

/// How a server that is already running (the Docker stack, usually) wants to be talked to.
enum LiveMode {
  /// Nothing answers: a test that needs a live server has nothing to run against.
  none,

  /// Plain HTTP works for everything (no TLS, or `HTTP_MODE=full`).
  plain,

  /// The plain port only serves the bootstrap routes (`HTTP_MODE=redirect`): the API is reached over HTTPS, trusting the CA
  /// the server itself hands out (it is the developer's own machine, so downloading it unchecked is what pairing is for).
  secure,
}

class LiveServer {
  LiveServer._(this.mode, this.base, this._client);

  final LiveMode mode;

  /// Where the API is, in the mode that works.
  final Uri base;
  final http.Client? _client;

  /// A client that can talk to [base] (the right trust for the mode).
  http.Client get client => _client ?? http.Client();

  void close() => _client?.close();

  @override
  String toString() => 'LiveServer($mode, $base)';
}

/// Looks at what is listening on [host]:[port] and says how to reach its API. It decides from what the server shows, not
/// from a setting of the test: no answer, plain HTTP, or HTTPS only. Never throws.
Future<LiveServer> findLiveServer({String host = 'localhost', int port = 8086, Duration timeout = const Duration(seconds: 2)}) async {
  final plain = Uri(scheme: 'http', host: host, port: port);
  final probe = http.Client();
  try {
    final info = await probe.get(plain.resolve('/server/info/')).timeout(timeout);
    // something else listening on that port (any other program) is not the server this is looking for
    if (info.statusCode != 200) return LiveServer._(LiveMode.none, plain, null);
    final tls = int.tryParse(info.headers['x-pindrel-tls'] ?? '');
    if (tls == null || tls < 1 || tls > 65535) return LiveServer._(LiveMode.plain, plain, null);
    // A harmless request that the plain port refuses with 426 when it only serves the bootstrap routes.
    final options = await probe.send(http.Request('OPTIONS', plain.resolve('/auth/login/'))).timeout(timeout);
    await options.stream.drain<void>();
    if (options.statusCode != 426) return LiveServer._(LiveMode.plain, plain, null);
    final ca = await probe.get(plain.resolve('/server/ca.pem')).timeout(timeout);
    final fp = ca.statusCode == 200 ? fingerprintOfPemOrNull(ca.body) : null;
    if (fp == null) return LiveServer._(LiveMode.none, plain, null);
    final server = PairedServer(hostPort: '$host:$tls', fingerprint: fp, caPem: ca.body, name: host);
    return LiveServer._(LiveMode.secure, Uri(scheme: 'https', host: host, port: tls), clientFor(server));
  } on Object {
    return LiveServer._(LiveMode.none, plain, null);
  } finally {
    probe.close();
  }
}
