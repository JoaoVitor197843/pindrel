import 'package:http/http.dart' as http;
import 'package:protobuf/protobuf.dart';

/// Names of the cookies the backend sends.
///
/// The access token is not a cookie: it comes in the response body and goes back in the
/// `Authorization: Bearer` header. If the backend starts sending other cookies, just
/// register them here; [ApiClient] already stores and resends any cookie.
abstract final class CookieNames {
  static const refreshToken = 'refresh_token';
}

/// Stores cookies by name (name -> value).
abstract interface class CookieStore {
  Future<Map<String, String>> readAll();
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

class MemoryCookieStore implements CookieStore {
  final Map<String, String> _cookies = {};

  @override
  Future<Map<String, String>> readAll() async => Map.unmodifiable(_cookies);

  @override
  Future<void> write(String name, String value) async {
    _cookies[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    _cookies.remove(name);
  }
}

/// A cookie read from a `Set-Cookie` header.
class SetCookie {
  const SetCookie({required this.name, required this.value, this.maxAge});

  final String name;
  final String value;
  final int? maxAge;

  /// The server clears a cookie by sending an empty value and/or `Max-Age` <= 0
  /// (which is what the backend's logout does).
  bool get isRemoval => value.isEmpty || (maxAge != null && maxAge! <= 0);
}

/// Reads the cookies from a `Set-Cookie` value.
///
/// `package:http` joins several `Set-Cookie` headers into a single comma-separated string,
/// and `Expires` also contains a comma (`Wed, 21 Oct ...`). That is why we only
/// split on commas followed by a new `name=`.
List<SetCookie> parseSetCookies(String? header) {
  if (header == null || header.isEmpty) return const [];

  final cookies = <SetCookie>[];
  for (final rawCookie in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
    final attributes = rawCookie.split(';').map((part) => part.trim()).toList();

    final nameValue = attributes.first;
    final separator = nameValue.indexOf('=');
    if (separator <= 0) continue;

    int? maxAge;
    for (final attribute in attributes.skip(1)) {
      if (attribute.toLowerCase().startsWith('max-age=')) {
        maxAge = int.tryParse(attribute.substring('max-age='.length));
      }
    }

    cookies.add(
      SetCookie(
        name: nameValue.substring(0, separator),
        value: nameValue.substring(separator + 1),
        maxAge: maxAge,
      ),
    );
  }
  return cookies;
}

class ApiClient {
  ApiClient({
    required this.client,
    required this.baseUrl,
    required this.cookies,
  });

  final String baseUrl;
  final http.Client client;
  final CookieStore cookies;

  Future<http.Response> postProto(String path, GeneratedMessage input) async {
    final response = await client.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/x-protobuf',
        ...await _cookieHeader(),
      },
      body: input.writeToBuffer(),
    );
    await _saveResponseCookies(response);
    return response;
  }

  /// `Cookie` header with all the stored cookies (empty if there are none).
  Future<Map<String, String>> _cookieHeader() async {
    final stored = await cookies.readAll();
    if (stored.isEmpty) return const {};
    final pairs = stored.entries.map((e) => '${e.key}=${e.value}');
    return {'Cookie': pairs.join('; ')};
  }

  Future<void> _saveResponseCookies(http.Response response) async {
    for (final cookie in parseSetCookies(response.headers['set-cookie'])) {
      if (cookie.isRemoval) {
        await cookies.delete(cookie.name);
      } else {
        await cookies.write(cookie.name, cookie.value);
      }
    }
  }
}
