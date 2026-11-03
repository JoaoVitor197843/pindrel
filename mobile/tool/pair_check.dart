// Pairs with a running server the way the app does and then talks to it over TLS trusting only its CA.
//   dart run tool/pair_check.dart 'pindrel://pair?host=192.168.1.5:8443&ca=<sha256>&n=Casa'
// (the code is printed by the gateway at start and shown as a QR code on /server/connect/)
import 'dart:io';

import 'package:mobile/core/network/pairing.dart';

Future<void> main(List<String> args) async {
  final code = args.isEmpty ? null : PairingCode.tryParse(args.first);
  if (code == null) {
    stderr.writeln('Uso: dart run tool/pair_check.dart "pindrel://pair?host=ip:porta&ca=<sha256>&n=<nome>"');
    exit(64);
  }
  final store = MemoryPairedStore();
  final result = await pair(code, store);
  switch (result) {
    case Paired(:final server):
      stdout.writeln('Código de conferência: ${code.confirmation} (deve ser igual ao da página e ao do log do servidor)');
      stdout.writeln('Pareado com "${server.name}" (${server.hostPort}), CA ${server.fingerprint.substring(0, 16)}…');
      final client = clientFor(server);
      try {
        final res = await client.get(code.baseUri.resolve('/server/info/'));
        stdout.writeln('GET /server/info/ -> ${res.statusCode}, id ${res.headers['x-pindrel-id']}');
      } finally {
        client.close();
      }
    case PairingFailed(:final reason):
      stdout.writeln('Pareamento recusado: $reason');
      exit(1);
  }
}
