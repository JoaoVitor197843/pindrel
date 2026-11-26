import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/auth_api.dart';
import '../../../core/network/pairing.dart';
import 'server_trust.dart';

/// How a server's [AuthApi] is built. Tests swap it for one over a fake client.
typedef AuthApiFactory = Future<AuthApi> Function(Uri server, CookieStore cookies);

/// The ordinary one: the client that trusts the CA this device paired with for that server (or the system roots). Each
/// [AuthApi] owns its client: [AuthSession] closes it once it is no longer used.
AuthApiFactory authApiFactory(PairedStore paired) => (server, cookies) async {
  final client = await clientForUri(server, paired);
  return AuthApi(ApiClient(client: client, baseUrl: server.origin, cookies: cookies));
};

enum AuthStatus { out, checking, signedIn }

/// Who is signed in on this device, and to which server. Mirrors the web's `Auth`: the access token lives only in memory;
/// the refresh token is a cookie. What is written to the secure storage is a note of the session (server and account) and
/// that cookie, and only when the person asked to stay signed in.
class AuthSession extends ChangeNotifier {
  AuthSession({
    required this._store,
    required AuthApiFactory apiFactory,
    this.minRenew = const Duration(seconds: 5),
    this.retryEvery = const Duration(seconds: 30),
  }) : _factory = apiFactory;

  static const storageKey = 'pindrel.session';

  /// The access token is renewed after this share of its life, so a slow answer never leaves a request without one.
  static const renewAt = 0.8;

  final KeyValueStore _store;
  final AuthApiFactory _factory;
  final Duration minRenew, retryEvery;

  AuthStatus _status = AuthStatus.out;
  Account? _user;
  Uri? _server;
  AuthApi? _api;
  CookieStore? _cookies;
  String? _token;
  Timer? _timer;
  Future<bool>? _renewing;

  /// Bumped by every sign-out, so an answer that arrives after it cannot bring the session back.
  int _epoch = 0;
  bool _disposed = false;

  AuthStatus get status => _status;
  Account? get user => _user;

  /// The server the session belongs to.
  Uri? get server => _server;

  /// Why the last session ended on its own (the server refused the renewal), until the next sign-in.
  bool endedByServer = false;

  void _set(AuthStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  void _adopt(Tokens t) {
    _token = t.accessToken;
    _timer?.cancel();
    final life = Duration(milliseconds: (t.expiresIn * 1000 * renewAt).round());
    _timer = Timer(life < minRenew ? minRenew : life, () => unawaited(_renew()));
  }

  /// [api] becomes the session's; the one it replaces is closed (a request of the old session still running fails, and
  /// nothing of the old session counts any more).
  void _use(AuthApi api) {
    if (!identical(_api, api)) _api?.close();
    _api = api;
  }

  void _signOutLocal({bool byServer = false}) {
    _epoch++;
    _api?.close();
    _api = null;
    _timer?.cancel();
    _token = null;
    _user = null;
    endedByServer = byServer;
    unawaited(_forgetNote());
    _set(AuthStatus.out);
  }

  Future<void> _forgetNote() async {
    try {
      await _store.write(storageKey, '');
    } catch (_) {}
  }

  Future<void> _remember(Account user, Uri server, CookieStore cookies) async {
    try {
      await _store.write(storageKey, jsonEncode({'server': server.origin, 'id': user.id, 'email': user.email, 'username': user.username, 'cookies': await cookies.readAll()}));
    } catch (_) {
      // storage blocked: the session lives until the app closes
    }
  }

  /// Asks for a new access token; false when it could not be had. Callers share one request.
  Future<bool> _renew() {
    final api = _api;
    // signed out meanwhile (a request refused while the person left): nothing to renew with
    if (api == null) return Future.value(false);
    return _renewing ??= _renewWith(api);
  }

  Future<bool> _renewWith(AuthApi api) async {
    final epoch = _epoch;
    try {
      final t = await api.refresh();
      // signed out, or another sign-in replaced this session meanwhile: the answer is not this session's
      if (epoch != _epoch || !identical(_api, api)) return false;
      _adopt(t);
      return true;
    } on AuthApiError catch (e) {
      if (epoch != _epoch || !identical(_api, api)) return false;
      if (e.isRefusal) {
        _signOutLocal(byServer: true);
      } else {
        // not a refusal: keep what there is and try again soon
        _timer?.cancel();
        _timer = Timer(e.retryAfter > retryEvery ? e.retryAfter : retryEvery, () => unawaited(_renew()));
      }
      return false;
    } finally {
      _renewing = null;
    }
  }

  /// Whether this device kept a session (the cookie may still be good). Never throws.
  Future<bool> get remembered async => (await _readNote()) != null;

  Future<Map<String, dynamic>?> _readNote() async {
    try {
      final raw = await _store.read(storageKey);
      if (raw == null || raw.isEmpty) return null;
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return null;
      final server = Uri.tryParse('${parsed['server']}');
      if (server == null || !server.hasAuthority || !const {'http', 'https'}.contains(server.scheme)) return null;
      if (parsed['id'] is! String || parsed['username'] is! String) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  /// On app start: turns the stored cookie back into a session. False means "show the notes of the device"; a refusal
  /// forgets the note, any other failure (no network) keeps it for the next start.
  Future<bool> restore() async {
    final note = await _readNote();
    if (note == null) return false;
    final server = Uri.parse(note['server'] as String);
    final cookies = MemoryCookieStore();
    final saved = note['cookies'];
    if (saved is Map) {
      for (final e in saved.entries) {
        if (e.key is String && e.value is String) await cookies.write(e.key as String, e.value as String);
      }
    }
    _set(AuthStatus.checking);
    final epoch = _epoch;
    AuthApi? api;
    try {
      api = await _factory(server, cookies);
      final t = await api.refresh();
      final user = await api.me(t.accessToken);
      if (epoch != _epoch) {
        api.close();
        return false;
      }
      _use(api);
      _cookies = cookies;
      _server = server;
      _user = user;
      _adopt(t);
      _set(AuthStatus.signedIn);
      return true;
    } on AuthApiError catch (e) {
      api?.close();
      if (e.isRefusal) await _forgetNote();
      if (epoch == _epoch) _set(AuthStatus.out);
      return false;
    } catch (_) {
      api?.close();
      if (epoch == _epoch) _set(AuthStatus.out);
      return false;
    }
  }

  /// Signs in to [server]. Throws [AuthApiError]; on success the session is set and the account returned.
  Future<Account> login(Uri server, String email, String password, {required bool keepSignedIn}) async {
    final epoch = _epoch;
    final cookies = MemoryCookieStore();
    final api = await _factory(server, cookies);
    final Tokens t;
    final Account user;
    try {
      t = await api.login(email, password, sessionOnly: !keepSignedIn);
      user = await api.me(t.accessToken);
      if (epoch != _epoch) throw const AuthApiError(0, 'cancelled');
    } catch (_) {
      api.close();
      rethrow;
    }
    _use(api);
    _cookies = cookies;
    _server = server;
    _user = user;
    endedByServer = false;
    _adopt(t);
    _set(AuthStatus.signedIn);
    // without "Manter conectado" nothing reaches the disk: closing the app ends the session
    if (keepSignedIn) {
      await _remember(user, server, cookies);
    } else {
      await _forgetNote();
    }
    return user;
  }

  /// Creates the account. It does not sign in: the server only creates it.
  Future<Account> register(Uri server, String email, String username, String password) async {
    final api = await _factory(server, MemoryCookieStore());
    try {
      return await api.register(email, username, password);
    } finally {
      api.close();
    }
  }

  /// Ends the session. The device is signed out even when the server cannot be reached.
  Future<void> logout() async {
    final api = _api, token = _token;
    _api = null; // kept open until the server was told
    _signOutLocal();
    try {
      await api?.logout(token);
    } catch (_) {
      // the cookie could not be revoked now; this device no longer uses it
    } finally {
      api?.close();
    }
  }

  /// Runs a request with the access token; one refusal renews the token and tries again, a second one signs out.
  Future<T> call<T>(Future<T> Function(String token) run) async {
    final token = _token;
    if (token == null) throw const AuthApiError(401, 'not_signed_in');
    try {
      return await run(token);
    } on AuthApiError catch (e) {
      if (e.status != 401) rethrow;
      if (!await _renew() || _token == null) rethrow;
      return run(_token!);
    }
  }

  /// The cookie jar of the live session (tests look at it).
  @visibleForTesting
  CookieStore? get cookiesForTest => _cookies;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _api?.close();
    _api = null;
    super.dispose();
  }
}
