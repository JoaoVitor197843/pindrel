// WebSocket from Dart (dart:io, what web_socket_channel uses on mobile/desktop): open time, message round trip, burst.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  final url = args[0];
  final opens = <double>[], rtts = <double>[], bursts = <double>[];
  for (var run = 0; run < 5; run++) {
    final sw = Stopwatch()..start();
    final ws = await WebSocket.connect(url, customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true);
    opens.add(sw.elapsedMicroseconds / 1000);
    final inbox = StreamController<dynamic>.broadcast();
    ws.listen(inbox.add);
    final payload = Uint8List(64);
    final samples = <double>[];
    for (var i = 0; i < 40; i++) {
      final t = Stopwatch()..start();
      final reply = inbox.stream.first;
      ws.add(payload);
      await reply;
      samples.add(t.elapsedMicroseconds / 1000);
    }
    samples.sort();
    rtts.add(samples[20]);
    var got = 0;
    final done = Completer<void>();
    final sub = inbox.stream.listen((_) {
      if (++got == 300) done.complete();
    });
    final b = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      ws.add(payload);
    }
    await done.future;
    bursts.add(b.elapsedMicroseconds / 1000);
    await sub.cancel();
    await ws.close();
  }
  double med(List<double> a) => (List.of(a)..sort())[a.length ~/ 2];
  print('${args[1].padRight(24)} abre=${med(opens).toStringAsFixed(0).padLeft(5)} ms  ida-e-volta=${med(rtts).toStringAsFixed(0).padLeft(4)} ms  300 msgs=${med(bursts).toStringAsFixed(0).padLeft(4)} ms  RSS=${(ProcessInfo.currentRss / (1 << 20)).toStringAsFixed(0)} MiB');
  exit(0);
}
