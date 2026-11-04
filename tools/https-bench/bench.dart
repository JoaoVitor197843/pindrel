// The same busy workload as mixed.mjs, from Dart (what the Flutter app's `http` package uses is dart:io's HttpClient).
// usage: dart run bin/bench.dart <mode: h1plain|h1tls|h2tls> <runs>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/http2.dart' as h2;

const plain = 9101, tls = 9444;

Uint8List loginBody(int run) {
  List<int> field(int n, String s) => [(n << 3) | 2, s.length, ...utf8.encode(s)];
  return Uint8List.fromList([...field(1, 'nobody$run@casa.local'), ...field(2, 'Wrong-pass-123!')]);
}

// path, method, body
List<(String, String, Uint8List?)> jobs(int run) => [
      for (var i = 0; i < 4; i++) ('/auth/login/', 'POST', loginBody(run)),
      for (var i = 0; i < 30; i++) ('/server/info/?n=$run-$i', 'GET', null),
      ('/assets/${Platform.environment['JS']}?cb=$run', 'GET', null),
      ('/assets/${Platform.environment['CHUNK']}?cb=$run', 'GET', null),
    ];

Future<List<double>> viaHttpClient(bool secure, int run) async {
  final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
  final port = secure ? tls : plain;
  final times = await Future.wait(jobs(run).map((j) async {
    final sw = Stopwatch()..start();
    final req = await (j.$2 == 'POST' ? client.postUrl : client.getUrl)(
        Uri.parse('${secure ? 'https' : 'http'}://localhost:$port${j.$1}'));
    if (j.$3 != null) {
      req.headers.contentType = ContentType('application', 'x-protobuf');
      req.add(j.$3!);
    }
    final res = await req.close();
    await res.drain<void>();
    return sw.elapsedMicroseconds / 1000;
  }));
  client.close(force: true);
  return times;
}

Future<List<double>> viaHttp2(int run) async {
  final socket = await SecureSocket.connect('localhost', tls,
      supportedProtocols: ['h2'], onBadCertificate: (_) => true);
  final conn = h2.ClientTransportConnection.viaSocket(socket);
  final times = await Future.wait(jobs(run).map((j) async {
    final sw = Stopwatch()..start();
    final stream = conn.makeRequest([
      h2.Header.ascii(':method', j.$2),
      h2.Header.ascii(':path', j.$1),
      h2.Header.ascii(':scheme', 'https'),
      h2.Header.ascii(':authority', 'localhost:$tls'),
      if (j.$3 != null) h2.Header.ascii('content-type', 'application/x-protobuf'),
    ], endStream: j.$3 == null);
    if (j.$3 != null) {
      stream.outgoingMessages.add(h2.DataStreamMessage(j.$3!, endStream: true));
    }
    await stream.incomingMessages.drain<void>();
    return sw.elapsedMicroseconds / 1000;
  }));
  await conn.finish();
  return times;
}

double pct(List<double> a, double p) => (List.of(a)..sort())[((a.length - 1) * p).floor()];

Future<void> main(List<String> args) async {
  final mode = args[0];
  final runs = int.parse(args[1]);
  final totals = <double>[], p95s = <double>[];
  for (var r = 0; r < runs; r++) {
    final sw = Stopwatch()..start();
    final times = switch (mode) {
      'h1plain' => await viaHttpClient(false, r),
      'h1tls' => await viaHttpClient(true, r),
      'h2tls' => await viaHttp2(r),
      _ => throw 'mode?',
    };
    totals.add(sw.elapsedMicroseconds / 1000);
    // the gateway allows 64 connections per address: let the previous run's ~36 sockets go before the next one opens its own
    await Future<void>.delayed(const Duration(seconds: 3));
    p95s.add(pct(times, 0.95));
  }
  final rss = ProcessInfo.currentRss / (1 << 20), peak = ProcessInfo.maxRss / (1 << 20);
  print('${mode.padRight(8)} tudo=${pct(totals, 0.5).toStringAsFixed(0).padLeft(5)} ms  p95=${pct(p95s, 0.5).toStringAsFixed(0).padLeft(5)} ms  '
      'pior=${totals.reduce((a, b) => a > b ? a : b).toStringAsFixed(0).padLeft(5)} ms  RSS=${rss.toStringAsFixed(0)} MiB (pico ${peak.toStringAsFixed(0)})');
}
