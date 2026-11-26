import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:protobuf/protobuf.dart';

import '../../shared/protos/auth.pb.dart';
import 'api_client.dart';

/// What went wrong, in the server's own words ([code]), or `network` / `timeout` / `tls` / `bad_reply` when nothing sensible
/// came back (same names as the web's `AuthApiError`).
class AuthApiError implements Exception {
  const AuthApiError(this.status, this.code, [this.retryAfter = Duration.zero]);

  /// 0 when no answer arrived.
  final int status;
  final String code;

  /// What the server asked to wait (`Retry-After`), zero when it did not.
  final Duration retryAfter;

  /// The server refused the credentials of the session (not a fault of the connection).
  bool get isRefusal => status == 401 || status == 403;

  @override
  String toString() => 'AuthApiError($status $code)';
}

class Tokens {
  const Tokens(this.accessToken, this.expiresIn);
  final String accessToken;

  /// Seconds the access token lives.
  final int expiresIn;
}

class Account {
  const Account({required this.id, required this.email, required this.username});
  final String id, email, username;

  @override
  bool operator ==(Object other) => other is Account && other.id == id && other.email == email && other.username == username;

  @override
  int get hashCode => Object.hash(id, email, username);
}

/// The auth routes of one server. The access token goes in the body and is the caller's to keep (in memory); the refresh
/// token is the `refresh_token` cookie, which [ApiClient] stores and sends back.
class AuthApi {
  AuthApi(this._api);
  final ApiClient _api;

  Future<http.Response> _call(String method, String path, {GeneratedMessage? body, String? token}) async {
    final http.Response res;
    try {
      res = await _api.send(method, path, body: body, token: token);
    } on TimeoutException {
      throw const AuthApiError(0, 'timeout');
    } on ReplyTooLarge {
      throw const AuthApiError(0, 'bad_reply');
    } on TlsException {
      // the certificate is not the one this device paired with
      throw const AuthApiError(0, 'tls');
    } on Object {
      // SocketException, http.ClientException (also what the http package wraps most failures in)...
      throw const AuthApiError(0, 'network');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    var code = 'http_error';
    try {
      final parsed = ErrorHttp.fromBuffer(res.bodyBytes).code;
      if (parsed.isNotEmpty) code = parsed;
    } catch (_) {
      // not a protobuf answer: the status is all there is
    }
    final seconds = int.tryParse(res.headers['retry-after'] ?? '') ?? 0;
    throw AuthApiError(res.statusCode, code, Duration(seconds: seconds.clamp(0, 60)));
  }

  Tokens _tokens(http.Response res) {
    try {
      final reply = LoginRefreshResponse.fromBuffer(res.bodyBytes);
      if (reply.accessToken.isNotEmpty) return Tokens(reply.accessToken, reply.expiresIn);
    } catch (_) {}
    throw AuthApiError(res.statusCode, 'bad_reply');
  }

  Account _account(UserSummary? user, int status) {
    if (user == null || user.id.isEmpty) throw AuthApiError(status, 'bad_reply');
    return Account(id: user.id, email: user.email, username: user.username);
  }

  Future<Account> register(String email, String username, String password) async {
    final res = await _call('POST', '/auth/register/', body: RegisterInput(email: email, username: username, password: password));
    try {
      return _account(RegisterResponse.fromBuffer(res.bodyBytes).user, res.statusCode);
    } on InvalidProtocolBufferException {
      throw AuthApiError(res.statusCode, 'bad_reply');
    }
  }

  /// [sessionOnly]: the refresh cookie must not outlive the app's session ("Manter conectado" off).
  Future<Tokens> login(String email, String password, {required bool sessionOnly}) async =>
      _tokens(await _call('POST', '/auth/login/', body: LoginInput(email: email, password: password, sessionOnly: sessionOnly)));

  /// A new access token from the stored refresh cookie.
  Future<Tokens> refresh() async => _tokens(await _call('POST', '/auth/refresh/'));

  Future<Account> me(String token) async {
    final res = await _call('GET', '/auth/me/', token: token);
    try {
      return _account(UserSummary.fromBuffer(res.bodyBytes), res.statusCode);
    } on InvalidProtocolBufferException {
      throw AuthApiError(res.statusCode, 'bad_reply');
    }
  }

  Future<void> logout(String? token) async {
    await _call('POST', '/auth/logout/', token: token);
  }

  /// Closes the HTTP client and its pooled connections; a request still running fails. Unused after this.
  void close() => _api.client.close();
}
