// ignore_for_file: avoid_print
// Pairs with a real server from the command line (the app's screens do the same with taps):
//   by room:   dart run tool/pair_digits.dart 192.168.1.163:8443 --room 4821 [--view-token <token>]
//   by master: dart run tool/pair_digits.dart 192.168.1.163:8443 --master XXXX-XXXX-XXXX-XXXX
// The room code and its token come from a page of the server (POST /server/pair/room). With --view-token the tool plays the
// person: it reads the digits that room shows (GET /server/pair/room with the token in a header, on the plain port given by
// --page, default the same host on 8086) and compares them with its own; without it, it asks you to compare.
import 'dart:convert';
import 'dart:io';

import 'package:mobile/core/network/pairing.dart';

String? option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || (option(args, '--room') == null && option(args, '--master') == null)) {
    stderr.writeln('uso: dart run tool/pair_digits.dart host:porta (--room 1234 [--view-token T] [--page host:porta] | --master CODIGO)');
    exit(64);
  }
  final i = args[0].lastIndexOf(':');
  final host = args[0].substring(0, i), port = int.parse(args[0].substring(i + 1));
  final store = MemoryPairedStore();

  final master = option(args, '--master');
  if (master != null) {
    final r = await pairWithMaster(host: host, port: port, master: master, store: store);
    _report(r);
    return;
  }

  final token = option(args, '--view-token');
  final page = option(args, '--page') ?? '$host:8086';
  final result = await pairWithDigits(
    host: host,
    port: port,
    room: option(args, '--room')!,
    store: store,
    confirm: (p) async {
      print('Servidor: ${p.name} (${p.hostPort})');
      print('Números no app:     ${p.grouped}');
      if (token != null) {
        final c = HttpClient();
        final req = await c.getUrl(Uri.parse('http://$page/server/pair/room'));
        req.headers.set('x-pindrel-room', token);
        final body = await (await req.close()).transform(utf8.decoder).join();
        c.close();
        final shown = RegExp(r'd=(\d{6}),').firstMatch(body)?.group(1);
        print('Números na página:  ${shown ?? '(nenhum)'}');
        return shown == p.digits;
      }
      stdout.write('São iguais aos da página de conexão do servidor? [s/N] ');
      // not readLineSync: it would freeze the whole program (sockets included) while the person compares
      final line = await stdin.transform(const SystemEncoding().decoder).transform(const LineSplitter()).first.catchError((_) => '');
      return line.trim().toLowerCase() == 's';
    },
  );
  _report(result);
}

void _report(PairingResult result) {
  switch (result) {
    case Paired(:final server):
      print('PAREADO. Chave ${server.fingerprint.substring(0, 16)}… confiável só para ${server.hostPort}.');
      print('Código de conferência: ${confirmationCode(server.fingerprint)}');
    case PairingFailed(:final reason):
      print('NÃO PAREADO: $reason');
      exit(1);
  }
}
