import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/core/api/auth_api.dart';
import 'package:mobile/features/auth/data/auth_session.dart';
import 'package:mobile/shared/protos/auth.pb.dart';

/// A stand-in for the Go API's auth routes, enough to drive [AuthSession] and the login form.
class FakeAuthServer {
  FakeAuthServer({this.expiresIn = 900});

  int expiresIn;
  final accounts = <String, ({String id, String username, String password})>{};
  var registrationOpen = true;

  /// Set to make the next calls to [path] answer this instead (until it returns null).
  final Map<String, http.Response Function(http.Request)> overrides = {};
  final requests = <String>[];
  int refreshes = 0;
  bool cookieValid = true;

  /// Held while set: calls wait for it (to race a sign-out against a slow login).
  Completer<void>? gate;

  http.Response _err(int status, String code, [Map<String, String> headers = const {}]) =>
      http.Response.bytes(ErrorHttp(code: code, message: code).writeToBuffer(), status, headers: headers);

  http.Response _tokens(String cookie) =>
      http.Response.bytes(LoginRefreshResponse(accessToken: 'access-${cookie.replaceFirst('cookie-', '')}-${requests.length}', expiresIn: expiresIn).writeToBuffer(), 200);

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    requests.add(key);
    if (gate != null) await gate!.future;
    final override = overrides[r.url.path];
    if (override != null) return override(r);
    switch (r.url.path) {
      case '/auth/register/':
        if (!registrationOpen) return _err(403, 'registration_disabled');
        final input = RegisterInput.fromBuffer(r.bodyBytes);
        if (accounts.containsKey(input.email)) return _err(409, 'email_already_exists');
        accounts[input.email] = (id: 'id-${accounts.length + 1}', username: input.username, password: input.password);
        return http.Response.bytes(RegisterResponse(user: UserSummary(id: accounts[input.email]!.id, email: input.email, username: input.username)).writeToBuffer(), 201);
      case '/auth/login/':
        final input = LoginInput.fromBuffer(r.bodyBytes);
        final account = accounts[input.email];
        if (account == null || account.password != input.password) return _err(401, 'invalid_credentials');
        return http.Response.bytes(
          LoginRefreshResponse(accessToken: 'access-${account.id}-${requests.length}', expiresIn: expiresIn).writeToBuffer(),
          200,
          headers: {'set-cookie': 'refresh_token=cookie-${account.id}; Path=/; HttpOnly${input.sessionOnly ? '' : '; Max-Age=2592000'}'},
        );
      case '/auth/refresh/':
        refreshes++;
        final cookie = RegExp(r'refresh_token=(cookie-[^;]+)').firstMatch(r.headers['Cookie'] ?? '')?.group(1);
        if (!cookieValid || cookie == null) return _err(401, 'invalid_refresh_token');
        return _tokens(cookie);
      case '/auth/me/':
        // the account is the one the token was issued to, as on the real server
        final id = RegExp(r'^Bearer access-(id-\d+)-').firstMatch(r.headers['Authorization'] ?? '')?.group(1);
        final entry = accounts.entries.where((e) => e.value.id == id).firstOrNull;
        if (entry == null) return _err(401, 'unauthorized');
        return http.Response.bytes(UserSummary(id: entry.value.id, email: entry.key, username: entry.value.username).writeToBuffer(), 200);
      case '/auth/logout/':
        return http.Response('', 204, headers: {'set-cookie': 'refresh_token=; Path=/; Max-Age=-1'});
    }
    return _err(404, 'not_found');
  }

  AuthApiFactory get factory =>
      (server, cookies) async => AuthApi(ApiClient(client: MockClient(handle), baseUrl: server.origin, cookies: cookies));
}
