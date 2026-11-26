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
  const PairedServer({required this.hostPort, required this.fingerprint, required this.caPem, required this.name, this.serverId = '', this.label = ''});

  final String hostPort;
  final String fingerprint;
  final String caPem;
  final String name;

  /// The id the server announces for itself (`x-pindrel-id`), empty when it announced none.
  final String serverId;

  /// The name the person gave it (optional); [name] stays the server's own, which is what remembering it by name relies on.
  final String label;

  /// What to call it on screen.
  String get shownName => label.isEmpty ? name : label;

  PairedServer withLabel(String value) =>
      PairedServer(hostPort: hostPort, fingerprint: fingerprint, caPem: caPem, name: name, serverId: serverId, label: cleanLabel(value));

  Map<String, String> toJson() => {'hostPort': hostPort, 'fingerprint': fingerprint, 'caPem': caPem, 'name': name, 'serverId': serverId, 'label': label};

  static PairedServer? fromJson(Object? json) {
    if (json is! Map) return null;
    final h = json['hostPort'], f = json['fingerprint'], c = json['caPem'], n = json['name'];
    if (h is! String || f is! String || c is! String || n is! String) return null;
    // only the certificate the fingerprint names is kept: older versions stored whatever followed it too
    final ca = firstCertificatePem(c);
    if (ca == null || fingerprintOfPem(ca) != f) return null; // a stored CA that is not the one it says it is is not used
    final id = json['serverId'], label = json['label'];
    return PairedServer(hostPort: h, fingerprint: f, caPem: ca, name: n, serverId: id is String ? id : '', label: label is String ? cleanLabel(label) : '');
  }
}

/// A name typed by a person: no control characters, spaces squeezed, at most [PairingCode.maxNameLength] characters.
String cleanLabel(String value) {
  final text = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > PairingCode.maxNameLength ? text.substring(0, PairingCode.maxNameLength).trim() : text;
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

final _certificateBlock = RegExp(r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----');

/// The DER of the first certificate in [pem]; `null` if there is none.
List<int>? _firstCertificateDer(String pem) {
  final m = _certificateBlock.firstMatch(pem);
  if (m == null) return null;
  try {
    return base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
}

/// SHA-256 of the DER of the first certificate in [pem], as 64 lower-case hex digits; `null` if there is none.
String? fingerprintOfPemOrNull(String pem) {
  final der = _firstCertificateDer(pem);
  return der == null ? null : sha256.convert(der).toString();
}

String fingerprintOfPem(String pem) => fingerprintOfPemOrNull(pem) ?? '';

/// The first certificate of [pem] alone, rebuilt as PEM; `null` if there is none.
///
/// The fingerprint a person vouches for (the QR code, the six digits, the master code's proofs) covers the first
/// certificate only, and TLS trusts every certificate of a PEM it is given. So nothing after the first one may ever be kept
/// or trusted: somebody in between could pass the real CA along and append their own.
String? firstCertificatePem(String pem) {
  final der = _firstCertificateDer(pem);
  if (der == null) return null;
  final b64 = base64.encode(der);
  final lines = [for (var i = 0; i < b64.length; i += 64) b64.substring(i, i + 64 > b64.length ? b64.length : i + 64)];
  return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n';
}

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

  /// The room code is not one the server has (a typo, one that expired, or one another device already joined).
  badRoom,

  /// Something answered at that address, but not as a Pindrel server (another kind of server, or a page of some site).
  notPindrel,

  /// The master code was refused, or the server could not prove it knows it: a wrong or spent code, or not the right server.
  badCode,
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
  final http = _UncheckedHttp(code.host, code.port, timeout);
  try {
    final (status, ca) = await http.ca();
    if (status != 200 || ca == null) return const PairingFailed(PairingFailure.notACertificate);
    final fp = fingerprintOfPem(ca);
    if (fp != code.fingerprint) return const PairingFailed(PairingFailure.fingerprintMismatch);
    final server = PairedServer(hostPort: code.hostPort, fingerprint: fp, caPem: ca, name: code.name);
    await store.save(server);
    return Paired(server);
  } on FormatException {
    return const PairingFailed(PairingFailure.notACertificate);
  } on Object catch (e) {
    if (_isNetworkFailure(e)) return const PairingFailed(PairingFailure.unreachable);
    rethrow;
  } finally {
    http.close();
  }
}

bool _isNetworkFailure(Object e) => e is TimeoutException || e is SocketException || e is HandshakeException || e is HttpException;

/// HTTPS to one host and port whose certificate cannot be checked yet (nothing to check it against before pairing): what
/// comes back counts only once a fingerprint the person vouched for matches. Answers are capped at [_maxCaBytes].
class _UncheckedHttp {
  _UncheckedHttp(this.host, this.port, this.timeout) : _client = _open(host, port, timeout);

  final String host;
  final int port;
  final Duration timeout;
  final HttpClient _client;

  static HttpClient _open(String host, int port, Duration timeout) => HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (_, h, p) => h == host && p == port;

  Uri _at(String path) => Uri(scheme: 'https', host: host, port: port, path: path);

  /// Status and body. A body over the cap is a [FormatException].
  Future<(int, String)> call(String method, String path, [String body = '']) => _send(_client, method, path, body);

  Future<(int, String)> _send(HttpClient client, String method, String path, String body) async {
    final request = await (method == 'GET' ? client.getUrl(_at(path)) : client.postUrl(_at(path))).timeout(timeout);
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

  /// The same request on a new connection (the old one may have died while it sat idle).
  Future<(int, String)> callFresh(String method, String path, [String body = '']) async {
    final fresh = _open(host, port, timeout);
    try {
      return await _send(fresh, method, path, body);
    } finally {
      fresh.close(force: true);
    }
  }

  /// The server's CA: the status and its first certificate alone, or `null` when the answer holds none.
  Future<(int, String?)> ca() async {
    final (status, pem) = await call('GET', '/server/ca.pem');
    return (status, status == 200 ? firstCertificatePem(pem) : null);
  }

  void close() => _client.close(force: true);
}

/// An HTTP client for [server]: it trusts that server's CA and nothing else (no system roots), so it only talks to it.
/// Only the first certificate of the stored PEM is trusted, the one its fingerprint names.
http.Client clientFor(PairedServer server) {
  final context = SecurityContext(withTrustedRoots: false);
  final ca = firstCertificatePem(server.caPem);
  if (ca != null) context.setTrustedCertificatesBytes(Uint8List.fromList(utf8.encode(ca)));
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
  required String room,
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
  required String room,
  required PairedStore store,
  required Future<bool> Function(SasPrompt prompt) confirm,
  Duration timeout = pairingTimeout,
  Duration confirmTimeout = sasConfirmTimeout,
  Random? random,
  String serverId = '',
}) async {
  final rng = random ?? Random.secure();
  final hostPort = host.contains(':') ? '[$host]:$port' : '$host:$port';
  final http = _UncheckedHttp(host, port, timeout);
  final call = http.call;

  try {
    final (caStatus, pem) = await http.ca();
    if (caStatus != 200 || pem == null) return const PairingFailed(PairingFailure.notACertificate);
    final fp = fingerprintOfPem(pem);

    final a = List<int>.generate(16, (_) => rng.nextInt(256));
    final (startStatus, startBody) = await call('POST', '/server/pair/start', 'c=${sha256.convert(a)}\nroom=$room\n');
    if (startStatus == 404) return const PairingFailed(PairingFailure.badRoom);
    if (startStatus == 429) return PairingFailed(startBody.contains('pairing_locked') ? PairingFailure.locked : PairingFailure.busy);
    if (startStatus != 200) return const PairingFailed(PairingFailure.protocol);
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
    // Tells the server the person has answered, so its page stops showing the digits and another device can pair. The
    // answer matters when the person said "same": 204 means that session was still the live one, i.e. the digits the person
    // compared are the ones the server was showing. 409 means it was replaced or expired meanwhile, and nothing is paired.
    Future<int?> finish() async {
      try {
        return (await call('POST', '/server/pair/done', 'id=$id\n')).$1;
      } on Object {
        // The connection sat idle while the person compared the screens and may be dead: once more, on a new one.
        try {
          return (await http.callFresh('POST', '/server/pair/done', 'id=$id\n')).$1;
        } on Object {
          return null;
        }
      }
    }

    final told = await finish();
    if (!same) return PairingFailed(expired ? PairingFailure.expired : PairingFailure.declined);
    if (told == 409) return const PairingFailed(PairingFailure.expired); // new digits are asked for, not a pairing on old ones
    if (told != 204) return const PairingFailed(PairingFailure.unreachable); // never pair on a confirmation the server did not acknowledge
    final server = PairedServer(hostPort: hostPort, fingerprint: fp, caPem: pem, name: name, serverId: serverId);
    await store.save(server);
    return Paired(server);
  } on FormatException {
    return const PairingFailed(PairingFailure.protocol);
  } on Object catch (e) {
    if (_isNetworkFailure(e)) return const PairingFailed(PairingFailure.unreachable);
    rethrow;
  } finally {
    http.close();
  }
}

/// The 80-bit master code the gateway prints in its log (`K7Q2-9XMD-4R8T-0HZ3`) from what a person types: any case, dashes and
/// spaces ignored, `O` read as `0` and `I`/`L` as `1` (Crockford base32). `null` when it is not exactly 16 such characters.
List<int>? parseMasterCode(String text) {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final symbols = <int>[];
  for (final rune in text.runes) {
    var c = String.fromCharCode(rune).toUpperCase();
    if (c == '-' || RegExp(r'\s').hasMatch(c)) continue;
    if (c == 'O') c = '0';
    if (c == 'I' || c == 'L') c = '1';
    final i = alphabet.indexOf(c);
    if (c.length != 1 || i < 0) return null;
    symbols.add(i);
  }
  if (symbols.length != 16) return null;
  final out = <int>[];
  var acc = 0, bits = 0;
  for (final s in symbols) {
    acc = (acc << 5) | s;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((acc >> bits) & 0xff);
      acc &= (1 << bits) - 1;
    }
  }
  return out;
}

/// The inverse, for the tests: 10 bytes as `XXXX-XXXX-XXXX-XXXX`.
String formatMasterCode(List<int> bytes) {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final out = StringBuffer();
  var acc = 0, bits = 0, n = 0;
  for (final b in bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      if (n > 0 && n % 4 == 0) out.write('-');
      out.write(alphabet[(acc >> bits) & 31]);
      n++;
    }
    acc &= (1 << bits) - 1;
  }
  return out.toString();
}

/// The proof one side gives the other (`tag` is `pindrel-master-a` from the app, `pindrel-master-s` from the server): an
/// HMAC-SHA256 keyed with the master code over the fingerprint of the CA as that side sees it and both fresh numbers.
List<int> masterProof(List<int> master, String tag, List<int> caFingerprint, List<int> nonceA, List<int> nonceS) =>
    Hmac(sha256, master).convert([...utf8.encode(tag), ...caFingerprint, ...nonceA, ...nonceS]).bytes;

bool _sameBytes(List<int>? a, List<int> b) {
  if (a == null || a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// The shape of [pairWithMaster], so a screen can be tested with a fake.
typedef MasterPairer = Future<PairingResult> Function({
  required String host,
  required int port,
  required String master,
  required PairedStore store,
  Duration timeout,
  Random? random,
  String serverId,
});

/// Pairs with the server using the master code its log shows, with nothing to compare: the app and the server prove to each
/// other that they know the code (an HMAC over the code, the CA each side sees and both fresh numbers) without sending it.
///
/// Somebody in between with another CA cannot produce the server's proof, and 80 bits cannot be searched from a proof that was
/// watched. The code works once and is replaced after, so a wrong, spent or expired one is refused ([PairingFailure.badCode]).
Future<PairingResult> pairWithMaster({
  required String host,
  required int port,
  required String master,
  required PairedStore store,
  Duration timeout = pairingTimeout,
  Random? random,
  String serverId = '',
}) async {
  final key = parseMasterCode(master);
  if (key == null) return const PairingFailed(PairingFailure.badCode);
  final rng = random ?? Random.secure();
  final hostPort = host.contains(':') ? '[$host]:$port' : '$host:$port';
  final http = _UncheckedHttp(host, port, timeout);
  final call = http.call;

  try {
    final (caStatus, pem) = await http.ca();
    if (caStatus != 200 || pem == null) return const PairingFailed(PairingFailure.notACertificate);
    final fp = fingerprintOfPem(pem);
    final fpBytes = _unhex(fp, 32)!;

    final a = List<int>.generate(16, (_) => rng.nextInt(256));
    final (startStatus, startBody) = await call('POST', '/server/pair/master/start', 'c=${sha256.convert(a)}\n');
    if (startStatus == 429) return PairingFailed(startBody.contains('pairing_locked') ? PairingFailure.locked : PairingFailure.busy);
    if (startStatus != 200) return const PairingFailed(PairingFailure.protocol);
    final id = _field(startBody, 'id');
    final s = _unhex(_field(startBody, 'n'), 16);
    if (_unhex(id, 16) == null || s == null) return const PairingFailed(PairingFailure.protocol);
    var name = _field(startBody, 'name').replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim();
    if (name.isEmpty || name.length > PairingCode.maxNameLength) name = host;

    final proof = masterProof(key, 'pindrel-master-a', fpBytes, a, s);
    final (status, body) = await call('POST', '/server/pair/master/finish', 'id=$id\na=${_hex(a)}\np=${_hex(proof)}\n');
    if (status == 403) return const PairingFailed(PairingFailure.badCode);
    if (status == 429) return const PairingFailed(PairingFailure.locked);
    if (status != 200) return const PairingFailed(PairingFailure.protocol);
    // the server's proof: only somebody who knows the code, over the CA this app saw, can have made it
    final theirs = _unhex(_field(body, 'p'), 32);
    if (!_sameBytes(theirs, masterProof(key, 'pindrel-master-s', fpBytes, a, s))) {
      return const PairingFailed(PairingFailure.badCode);
    }
    final server = PairedServer(hostPort: hostPort, fingerprint: fp, caPem: pem, name: name, serverId: serverId);
    await store.save(server);
    return Paired(server);
  } on FormatException {
    return const PairingFailed(PairingFailure.protocol);
  } on Object catch (e) {
    if (_isNetworkFailure(e)) return const PairingFailed(PairingFailure.unreachable);
    rethrow;
  } finally {
    http.close();
  }
}
