import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/data/server_option.dart';

import '../../support/discovery_fakes.dart';

void main() {
  test('vem do servidor achado: endereço com porta e URL da API', () {
    final option = ServerOption.fromDiscovered(
      server('Escritório', addresses: ['192.168.0.20'], port: 8095),
    );
    expect(option.id, 'escritorio');
    expect(option.name, 'Escritório');
    expect(option.address, '192.168.0.20:8095');
    expect(option.baseUri, Uri.parse('http://192.168.0.20:8095'));
  });

  test('o id é estável, sem acento nem símbolos', () {
    expect(ServerOption.idFor('Casa do João #2'), 'casa-do-joao-2');
    expect(ServerOption.idFor('  Plany!  '), 'plany');
    expect(ServerOption.idFor('Ação'), 'acao');
    expect(ServerOption.idFor('???'), 'servidor');
  });

  test('dois são o mesmo servidor quando têm o mesmo id', () {
    final a = ServerOption.fromDiscovered(
      server('Casa', addresses: ['10.0.0.1']),
    );
    final b = ServerOption.fromDiscovered(
      server('Casa', addresses: ['10.0.0.9']),
    );
    expect(a, b);
  });
}
