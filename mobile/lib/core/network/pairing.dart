import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// What a QR code (or a pasted text) of the connection page carries:
/// `pindrel://pair?host=192.168.1.5:8443&ca=<sha256 of the server's CA>&n=<name>`.
///
/// Out of band, on purpose: the fingerprint is what makes the CA that is downloaded afterwards trustworthy. Whoever else
/// answers on that address can serve any certificate, but not one whose SHA-256 is this.
class PairingCode {
  const PairingCode({required this.host, required this.port, required this.fingerprint, required this.name});

  final String host;
  final int port;
  final String fingerprint;
  final String name;

  static const maxLength = 512;
  static const maxNameLength = 64;
  static final _hex = RegExp(r'^[0-9a-f]{64}$');
  static final _hostName = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$');

  /// `null` for anything that is not exactly a pairing code.
  static PairingCode? tryParse(String input) {
    final text = input.trim();
    if (text.isEmpty || text.length > maxLength || text.contains(RegExp(r'\s'))) return null;
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }
    if (uri.scheme != 'pindrel' || uri.host != 'pair' || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    final Map<String, List<String>> q;
    try {
      q = uri.queryParametersAll;
    } on FormatException {
      return null;
    }
    for (final key in q.keys) {
      if (!const {'host', 'ca', 'n'}.contains(key) || q[key]!.length != 1) return null;
    }
    final hostPort = q['host']?.single;
    final ca = q['ca']?.single.toLowerCase();
    if (hostPort == null || ca == null || !_hex.hasMatch(ca)) return null;
    final name = (q['n']?.single ?? '').trim();
    if (name.length > maxNameLength) return null;
    final split = _splitHostPort(hostPort);
    if (split == null) return null;
    return PairingCode(host: split.$1, port: split.$2, fingerprint: ca, name: name);
  }

  static (String, int)? _splitHostPort(String value) {
    final String host;
    final String port;
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end < 0 || value.length <= end + 2 || value[end + 1] != ':') return null;
      host = value.substring(1, end);
      port = value.substring(end + 2);
      if (InternetAddress.tryParse(host)?.type != InternetAddressType.IPv6) return null;
    } else {
      final i = value.lastIndexOf(':');
      if (i <= 0) return null;
      host = value.substring(0, i).toLowerCase();
      port = value.substring(i + 1);
      final ip = InternetAddress.tryParse(host);
      if (ip == null && (!_hostName.hasMatch(host) || RegExp(r'^[0-9.]+$').hasMatch(host))) return null; // 999.1.1.1 is not a name
      if (ip != null && ip.type != InternetAddressType.IPv4) return null;
      if (host.length > 253) return null;
    }
    if (!RegExp(r'^\d{1,5}$').hasMatch(port)) return null;
    final p = int.parse(port);
    return p >= 1 && p <= 65535 ? (host, p) : null;
  }

  /// `host:port`, with brackets around an IPv6 address.
  String get hostPort => host.contains(':') ? '[$host]:$port' : '$host:$port';

  /// What to show the person so they can compare it with the server's page: see [confirmationCode].
  String get confirmation => confirmationCode(fingerprint);

  Uri get baseUri => Uri(scheme: 'https', host: host, port: port);
}

/// The short code people compare with the one on the server's connection page and in its log: the first 48 bits of the
/// fingerprint as `3DC3-39F4-232A`. Empty when the fingerprint is not long enough to give one.
String confirmationCode(String fingerprint) {
  if (fingerprint.length < 12 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(fingerprint)) return '';
  final up = fingerprint.toUpperCase();
  return '${up.substring(0, 4)}-${up.substring(4, 8)}-${up.substring(8, 12)}';
}

/// A server this device has paired with: only its CA is trusted, and only for it.
class PairedServer {
  const PairedServer({required this.hostPort, required this.fingerprint, required this.caPem, required this.name, this.serverId = ''});

  final String hostPort;
  final String fingerprint;
  final String caPem;
  final String name;

  /// The id the server announces for itself (`x-pindrel-id`), empty when it announced none.
  final String serverId;

  Map<String, String> toJson() => {'hostPort': hostPort, 'fingerprint': fingerprint, 'caPem': caPem, 'name': name, 'serverId': serverId};

  static PairedServer? fromJson(Object? json) {
    if (json is! Map) return null;
    final h = json['hostPort'], f = json['fingerprint'], c = json['caPem'], n = json['name'];
    if (h is! String || f is! String || c is! String || n is! String) return null;
    if (fingerprintOfPem(c) != f) return null; // a stored CA that is not the one it says it is is not used
    final id = json['serverId'];
    return PairedServer(hostPort: h, fingerprint: f, caPem: c, name: n, serverId: id is String ? id : '');
  }
}

/// Where pairings are kept between runs (the app uses secure storage).
abstract interface class PairedStore {
  Future<PairedServer?> find(String hostPort);
  Future<List<PairedServer>> all();
  Future<void> save(PairedServer server);
  Future<void> forget(String hostPort);
}

class MemoryPairedStore implements PairedStore {
  final Map<String, PairedServer> _items = {};

  @override
  Future<PairedServer?> find(String hostPort) async => _items[hostPort];

  @override
  Future<List<PairedServer>> all() async => _items.values.toList();

  @override
  Future<void> save(PairedServer server) async => _items[server.hostPort] = server;

  @override
  Future<void> forget(String hostPort) async => _items.remove(hostPort);
}

/// SHA-256 of the DER of the first certificate in [pem], as 64 lower-case hex digits; `null` if there is none.
String? fingerprintOfPemOrNull(String pem) {
  final m = RegExp(r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----').firstMatch(pem);
  if (m == null) return null;
  try {
    return sha256.convert(base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''))).toString();
  } on FormatException {
    return null;
  }
}

String fingerprintOfPem(String pem) => fingerprintOfPemOrNull(pem) ?? '';

sealed class PairingResult {
  const PairingResult();
}

class Paired extends PairingResult {
  const Paired(this.server);
  final PairedServer server;
}

enum PairingFailure {
  /// Nobody answered, or not in time.
  unreachable,

  /// Something answered, but what it sent is not the CA the code names: a different server, or someone in between.
  fingerprintMismatch,

  /// Something answered, but not with a certificate.
  notACertificate,

  /// Another device is pairing with that server right now (try again in a minute).
  busy,

  /// Too many failed attempts from this device: the server asks it to wait.
  locked,

  /// The person said the numbers were different.
  declined,

  /// Nobody answered before the digits expired (the server drops a session after a minute): ask again for new ones.
  expired,

  /// The server answered something the protocol does not say: another program, or a different version.
  protocol,
}

class PairingFailed extends PairingResult {
  const PairingFailed(this.reason);
  final PairingFailure reason;
}

const pairingTimeout = Duration(seconds: 5);
const _maxCaBytes = 16 * 1024;

/// Asks the server in [code] for its CA and keeps it only if it is the one the code names.
///
/// The download itself is the one place where the certificate is not checked (there is nothing to check it against yet):
/// that is safe because what comes back is only used if its SHA-256 equals the fingerprint the person scanned.
Future<PairingResult> pair(PairingCode code, PairedStore store, {Duration timeout = pairingTimeout}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  client.badCertificateCallback = (_, host, port) => host == code.host && port == code.port;
  try {
    final request = await client.getUrl(code.baseUri.resolve('/server/ca.pem')).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return const PairingFailed(PairingFailure.notACertificate);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > _maxCaBytes) return const PairingFailed(PairingFailure.notACertificate);
    }
    final String pem;
    try {
      pem = utf8.decode(bytes.takeBytes());
    } on FormatException {
      return const PairingFailed(PairingFailure.notACertificate);
    }
    final fp = fingerprintOfPemOrNull(pem);
    if (fp == null) return const PairingFailed(PairingFailure.notACertificate);
    if (fp != code.fingerprint) return const PairingFailed(PairingFailure.fingerprintMismatch);
    final server = PairedServer(hostPort: code.hostPort, fingerprint: fp, caPem: pem, name: code.name);
    await store.save(server);
    return Paired(server);
  } on TimeoutException {
    return const PairingFailed(PairingFailure.unreachable);
  } on SocketException {
    return const PairingFailed(PairingFailure.unreachable);
  } on HandshakeException {
    return const PairingFailed(PairingFailure.unreachable);
  } on HttpException {
    return const PairingFailed(PairingFailure.unreachable);
  } finally {
    client.close(force: true);
  }
}

/// An HTTP client for [server]: it trusts that server's CA and nothing else (no system roots), so it only talks to it.
http.Client clientFor(PairedServer server) {
  final context = SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(Uint8List.fromList(utf8.encode(server.caPem)));
  return IOClient(HttpClient(context: context));
}

/// The client to use for [baseUri]: the paired one when this device paired with that server, the ordinary one otherwise.
Future<http.Client> clientForUri(Uri baseUri, PairedStore store) async {
  final key = baseUri.host.contains(':') ? '[${baseUri.host}]:${baseUri.port}' : '${baseUri.host}:${baseUri.port}';
  final paired = baseUri.scheme == 'https' ? await store.find(key) : null;
  return paired == null ? http.Client() : clientFor(paired);
}

/// What the person sees while pairing by digits: compare [digits] with the ones on the server's connection page.
class SasPrompt {
  const SasPrompt({required this.digits, required this.name, required this.hostPort, required this.expiresAt});
  final String digits;

  /// When the server forgets these digits: past it the person is given new ones.
  final DateTime expiresAt;
  final String name;
  final String hostPort;

  /// `123 456`, easier to read and to say aloud.
  String get grouped => '${digits.substring(0, 3)} ${digits.substring(3)}';
}

/// The six digits both sides compute (see `gateway/src/pairing.rs`, which has the protocol and the reasoning): a hash of the
/// fingerprint of the CA that was downloaded and of both random numbers, reduced to six decimal digits.
String sasDigits(List<int> caFingerprint, List<int> nonceA, List<int> nonceS) {
  final d = sha256.convert([...utf8.encode('pindrel-sas-v1'), ...caFingerprint, ...nonceA, ...nonceS]).bytes;
  final n = (d[0] << 24 | d[1] << 16 | d[2] << 8 | d[3]) % 1000000;
  return n.toString().padLeft(6, '0');
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int>? _unhex(String text, int length) {
  if (text.length != length * 2 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) return null;
  return [for (var i = 0; i < length; i++) int.parse(text.substring(i * 2, i * 2 + 2), radix: 16)];
}

String _field(String body, String key) {
  for (final line in const LineSplitter().convert(body)) {
    final i = line.indexOf('=');
    if (i > 0 && line.substring(0, i) == key) return line.substring(i + 1).trim();
  }
  return '';
}

/// The shape of [pairWithDigits], so a screen can be tested with a fake.
typedef DigitsPairer = Future<PairingResult> Function({
  required String host,
  required int port,
  required PairedStore store,
  required Future<bool> Function(SasPrompt prompt) confirm,
  Duration timeout,
  Duration confirmTimeout,
  Random? random,
  String serverId,
});

/// How long the person has to compare and answer: just under the server's own 60 s, so the app asks for new digits before
/// the server forgets the old ones.
const sasConfirmTimeout = Duration(seconds: 58);

/// Pairs with the server at [host]:[port] by comparing six digits, with no camera and no code to type.
///
/// 1. The CA is downloaded without being checked (nothing to check it against yet) and its fingerprint is taken.
/// 2. The app commits to a random number, the server answers with its own, the app reveals its number.
/// 3. Both sides compute the same six digits only if they hold the same CA; [confirm] shows them to the person, who compares
///    with the server's connection page and answers. Only on "same" is the CA kept (and trusted for that server alone).
///
/// Somebody in between presents another CA, gets other digits and cannot choose them: see the protocol notes in the gateway.
Future<PairingResult> pairWithDigits({
  required String host,
  required int port,
  required PairedStore store,
  required Future<bool> Function(SasPrompt prompt) confirm,
  Duration timeout = pairingTimeout,
  Duration confirmTimeout = sasConfirmTimeout,
  Random? random,
  String serverId = '',
}) async {
  final rng = random ?? Random.secure();
  final base = Uri(scheme: 'https', host: host, port: port);
  final hostPort = host.contains(':') ? '[$host]:$port' : '$host:$port';
  final client = HttpClient()..connectionTimeout = timeout;
  client.badCertificateCallback = (_, h, p) => h == host && p == port;

  Future<(int, String)> call(String method, String path, [String body = '']) async {
    final request = await (method == 'GET' ? client.getUrl(base.resolve(path)) : client.postUrl(base.resolve(path))).timeout(timeout);
    if (method == 'POST') {
      request.headers.contentType = ContentType.text;
      request.write(body);
    }
    final response = await request.close().timeout(timeout);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > _maxCaBytes) throw const FormatException('answer too large');
    }
    return (response.statusCode, utf8.decode(bytes.takeBytes(), allowMalformed: true));
  }

  PairingFailed? refusal(int status) => switch (status) {
        429 => const PairingFailed(PairingFailure.busy),
        _ => const PairingFailed(PairingFailure.protocol),
      };

  try {
    final (caStatus, pem) = await call('GET', '/server/ca.pem');
    if (caStatus != 200) return const PairingFailed(PairingFailure.notACertificate);
    final fp = fingerprintOfPemOrNull(pem);
    if (fp == null) return const PairingFailed(PairingFailure.notACertificate);

    final a = List<int>.generate(16, (_) => rng.nextInt(256));
    final (startStatus, startBody) = await call('POST', '/server/pair/start', 'c=${sha256.convert(a)}\n');
    if (startStatus == 429) return PairingFailed(startBody.contains('pairing_locked') ? PairingFailure.locked : PairingFailure.busy);
    if (startStatus != 200) return refusal(startStatus)!;
    final id = _field(startBody, 'id');
    final s = _unhex(_field(startBody, 'n'), 16);
    if (_unhex(id, 16) == null || s == null) return const PairingFailed(PairingFailure.protocol);
    var name = _field(startBody, 'name').replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim();
    if (name.isEmpty || name.length > PairingCode.maxNameLength) name = host;

    final (revealStatus, _) = await call('POST', '/server/pair/reveal', 'id=$id\na=${_hex(a)}\n');
    if (revealStatus == 429) return const PairingFailed(PairingFailure.locked);
    if (revealStatus != 204) return const PairingFailed(PairingFailure.protocol);

    final digits = sasDigits(_unhex(fp, 32)!, a, s);
    bool same;
    var expired = false;
    try {
      same = await confirm(SasPrompt(digits: digits, name: name, hostPort: hostPort, expiresAt: DateTime.now().add(confirmTimeout))).timeout(confirmTimeout);
    } on TimeoutException {
      same = false;
      expired = true;
    }
    // Best effort: tells the server the person has answered, so its page stops showing the digits and another device can
    // pair. The server drops the session by itself after a minute if this never arrives.
    try {
      await call('POST', '/server/pair/done', 'id=$id\n');
    } on Object {
      // nothing to do about it
    }
    if (!same) return PairingFailed(expired ? PairingFailure.expired : PairingFailure.declined);
    final server = PairedServer(hostPort: hostPort, fingerprint: fp, caPem: pem, name: name, serverId: serverId);
    await store.save(server);
    return Paired(server);
  } on TimeoutException {
    return const PairingFailed(PairingFailure.unreachable);
  } on SocketException {
    return const PairingFailed(PairingFailure.unreachable);
  } on HandshakeException {
    return const PairingFailed(PairingFailure.unreachable);
  } on HttpException {
    return const PairingFailed(PairingFailure.unreachable);
  } on FormatException {
    return const PairingFailed(PairingFailure.protocol);
  } finally {
    client.close(force: true);
  }
}
