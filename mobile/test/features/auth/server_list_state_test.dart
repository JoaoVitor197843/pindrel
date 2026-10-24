import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/data/server_list_state.dart';
import 'package:mobile/features/auth/data/server_option.dart';

const casa = ServerOption(id: 'casa', name: 'Casa', address: '10.0.0.1:80');

void main() {
  test('sem servidor escolhido: nada conectado, nada desconectado', () {
    const state = ServerListState();
    expect(state.connection, ServerConnection.none);
    expect(state.disconnected, isEmpty);
    expect(state.available, isEmpty);
    expect(state.searchError, isNull);
  });

  test('escolhido e na rede: conectado e fora da lista de desconectados', () {
    const state = ServerListState(
      available: [casa],
      selected: casa,
      selectedConnected: true,
    );
    expect(state.connection, ServerConnection.connected);
    expect(state.disconnected, isEmpty);
  });

  test(
    'escolhido que saiu da rede continua escolhido e aparece desconectado',
    () {
      const state = ServerListState(selected: casa);
      expect(state.connection, ServerConnection.disconnected);
      expect(state.disconnected, [casa]);
    },
  );

  // selectedConnected without selected is an incoherent state: it must not break
  test('"conectado" sem servidor escolhido não quebra e vale como nenhum', () {
    const state = ServerListState(selectedConnected: true);
    expect(state.connection, ServerConnection.none);
    expect(state.disconnected, isEmpty);
  });

  test('guarda o erro da busca sem mexer no resto', () {
    final error = StateError('sem permissão');
    final state = ServerListState(searchError: error);
    expect(state.searchError, error);
    expect(state.connection, ServerConnection.none);
  });
}
