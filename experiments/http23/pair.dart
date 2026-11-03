// Pairing as the app would do it: a code (host:port + the SHA-256 of the server's CA) is given out of band; the CA is
// fetched over plain HTTP (it is public) and trusted only if it matches the code; after that the app talks TLS to that
// server and to nothing else, with no system roots and no "accept any certificate".
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String fingerprintOfPem(String pem) {
  final b64 = pem.split('\n').where((l) => l.isNotEmpty && !l.startsWith('-----')).join();
  return sha256.convert(base64.decode(b64)).toString();
}

/// Returns the CA PEM when it matches [fingerprint]; null otherwise.
Future<String?> pair({required String host, required int plainPort, required String fingerprint}) async {
  final c = HttpClient();
  try {
    final res = await (await c.getUrl(Uri.parse('http://$host:$plainPort/server/ca.pem'))).close();
    if (res.statusCode != 200) return null;
    final pem = await utf8.decodeStream(res);
    return fingerprintOfPem(pem) == fingerprint ? pem : null;
  } finally {
    c.close(force: true);
  }
}

Future<String> get(String ca, String url) async {
  final ctx = SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(Uint8List.fromList(utf8.encode(ca)));
  final c = HttpClient(context: ctx);
  try {
    final res = await (await c.getUrl(Uri.parse(url))).close();
    await res.drain<void>();
    return 'ok ${res.statusCode}';
  } on HandshakeException catch (e) {
    return 'RECUSADO (${e.message.replaceAll(RegExp(r'\s+'), ' ').split('[').last.split('(').first.trim()})';
  } catch (e) {
    return 'erro: $e';
  } finally {
    c.close(force: true);
  }
}

Future<void> main(List<String> a) async {
  final cmd = a[0];
  final host = a[1];
  final plain = int.parse(a[2]);
  final tls = int.parse(a[3]);
  final fp = a[4];
  if (cmd == 'pair') {
    final ca = await pair(host: host, plainPort: plain, fingerprint: fp);
    print(ca == null ? 'PAREAMENTO RECUSADO: o CA não bate com o código' : 'pareado, CA ${fingerprintOfPem(ca).substring(0, 16)}…');
    if (ca != null) {
      File(a[5]).writeAsStringSync(ca);
      print('  conexão TLS: ${await get(ca, 'https://$host:$tls/server/info/')}');
    }
  } else if (cmd == 'use') {
    print('  conexão TLS com o CA guardado: ${await get(File(a[5]).readAsStringSync(), 'https://$host:$tls/server/info/')}');
  }
}
