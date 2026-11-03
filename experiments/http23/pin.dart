// Option 3: a self-signed (or any) server certificate, pinned by the SHA-256 of the certificate itself. Cheap, but the pin
// is the certificate, so every renewal or address change asks for a new pairing.
import 'dart:io';
import 'package:crypto/crypto.dart';

Future<String> tryPin(String pin, int port) async {
  final c = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..badCertificateCallback = (cert, host, p) => sha256.convert(cert.der).toString() == pin;
  try {
    final res = await (await c.getUrl(Uri.parse('https://127.0.0.1:$port/server/info/'))).close();
    await res.drain<void>();
    return 'ok ${res.statusCode}';
  } on HandshakeException {
    return 'RECUSADO (o certificado não é o fixado)';
  } finally {
    c.close(force: true);
  }
}

Future<void> main(List<String> a) async {
  if (a[0] == 'pin') {
    // trust on first use: learn the pin from whatever the server presents now
    String? got;
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false))..badCertificateCallback = (cert, h, p) { got = sha256.convert(cert.der).toString(); return true; };
    final res = await (await c.getUrl(Uri.parse('https://127.0.0.1:${a[1]}/server/info/'))).close();
    await res.drain<void>();
    print(got);
  } else {
    print(await tryPin(a[1], int.parse(a[2])));
  }
}
