import 'package:http/http.dart' as http;
import 'package:protobuf/protobuf.dart';

/// Nomes dos cookies que o backend envia.
///
/// O access token não é cookie: vem no corpo da resposta e volta no header
/// `Authorization: Bearer`. Se o backend passar a enviar outros cookies, basta
/// registrá-los aqui; o [ApiClient] já guarda e reenvia qualquer cookie.
abstract final class CookieNames {
  static const refreshToken = 'refresh_token';
}

/// Armazena cookies por nome (nome -> valor).
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

/// Um cookie lido de um header `Set-Cookie`.
class SetCookie {
  const SetCookie({required this.name, required this.value, this.maxAge});

  final String name;
  final String value;
  final int? maxAge;

  /// O servidor limpa um cookie enviando valor vazio e/ou `Max-Age` <= 0
  /// (é o que o logout do backend faz).
  bool get isRemoval => value.isEmpty || (maxAge != null && maxAge! <= 0);
}

/// Lê os cookies de um valor de `Set-Cookie`.
///
/// O `package:http` junta vários `Set-Cookie` em uma única string separada por
/// vírgula, e `Expires` também contém vírgula (`Wed, 21 Oct ...`). Por isso só
/// se separa em vírgulas seguidas de um novo `nome=`.
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

  /// Header `Cookie` com todos os cookies guardados (vazio se não houver).
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
