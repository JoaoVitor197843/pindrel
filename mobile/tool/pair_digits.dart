// ignore_for_file: avoid_print
// Pairs with a real server by comparing six digits, from the command line (the app's screen does not exist yet):
//   dart run tool/pair_digits.dart 192.168.1.163:8443
//   dart run tool/pair_digits.dart 192.168.1.163:8443 --compare-with http://192.168.1.163:8086/server/pair/sas
// Without --compare-with it asks you to compare the digits with the server's connection page; with it, it plays the person
// and compares with what that page serves (useful in scripts).
import 'dart:convert';
import 'dart:io';

import 'package:mobile/core/network/pairing.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('uso: dart run tool/pair_digits.dart host:porta [--compare-with URL]');
    exit(64);
  }
  final i = args[0].lastIndexOf(':');
  final host = args[0].substring(0, i), port = int.parse(args[0].substring(i + 1));
  final compare = args.length >= 3 && args[1] == '--compare-with' ? Uri.parse(args[2]) : null;
  final store = MemoryPairedStore();

  final result = await pairWithDigits(
    host: host,
    port: port,
    store: store,
    confirm: (p) async {
      print('Servidor: ${p.name} (${p.hostPort})');
      print('Números no app:     ${p.grouped}');
      if (compare != null) {
        final c = HttpClient();
        final r = await (await c.getUrl(compare)).close();
        final body = await r.transform(const SystemEncoding().decoder).join();
        c.close();
        final shown = RegExp(r'sas=(\d{6})').firstMatch(body)?.group(1);
        print('Números na página:  ${shown ?? '(nenhum)'}');
        return shown == p.digits;
      }
      stdout.write('São iguais aos da página de conexão do servidor? [s/N] ');
      // not readLineSync: it would freeze the whole program (sockets included) while the person compares
      final line = await stdin.transform(const SystemEncoding().decoder).transform(const LineSplitter()).first.catchError((_) => '');
      return line.trim().toLowerCase() == 's';
    },
  );
  switch (result) {
    case Paired(:final server):
      print('PAREADO. Chave ${server.fingerprint.substring(0, 16)}… confiável só para ${server.hostPort}.');
      print('Código de conferência: ${confirmationCode(server.fingerprint)}');
    case PairingFailed(:final reason):
      print('NÃO PAREADO: $reason');
      exit(1);
  }
}
