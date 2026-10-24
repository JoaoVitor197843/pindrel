import 'dart:async';
import 'dart:math';

import '../../../core/network/discovery/discovered_server.dart';
import '../../../core/network/discovery/server_discovery.dart';
import '../../../core/network/server_probe.dart';
import 'server_list_state.dart';
import 'server_option.dart';

/// Junta a descoberta de servidores com a escolha do usuário e entrega o
/// resultado como um [Stream] de [ServerListState], que a tela consome com
/// `StreamBuilder`.
///
/// A descoberta é assinada uma só vez, aqui; quem quiser acompanhar a lista
/// (botão, menu aberto, rodapé) assina [stream], que aceita vários ouvintes.
///
/// O servidor escolhido não some quando sai da rede: fica escolhido e passa a
/// contar como desconectado, e volta a conectado se for anunciado de novo.
class ServerListController {
  ServerListController({
    required ServerDiscovery discovery,
    Random? random,
    this.probe,
  }) : _random = random ?? Random() {
    _subscription = discovery.watch().listen(_onFound, onError: _onError);
  }

  final Random _random;

  /// Testa o servidor antes de escolhê-lo; sem ela a escolha é imediata.
  final ServerProbe? probe;
  ServerOption? _connecting;
  bool _loaded = false;
  late final StreamSubscription<List<DiscoveredServer>> _subscription;
  final StreamController<ServerListState> _out =
      StreamController<ServerListState>.broadcast();

  List<ServerOption> _available = const [];
  ServerOption? _selected;
  Object? _error;
  ServerListState _current = const ServerListState();

  /// O estado de agora (para o `initialData` do `StreamBuilder`).
  ServerListState get current => _current;

  /// Emite o estado novo a cada mudança.
  Stream<ServerListState> get stream => _out.stream;

  /// O usuário escolheu [server] (um disponível, ou o desconectado que já era o
  /// escolhido). Um servidor novo é testado antes ([ServerListState.connecting]
  /// enquanto espera); se não responde, a escolha anterior fica e devolve falso.
  Future<bool> select(ServerOption server) async {
    final probe = this.probe;
    final uri = server.baseUri;
    if (probe == null || uri == null || server == _selected) {
      _selected = server;
      _publish();
      return true;
    }
    if (_connecting != null) return false;
    _connecting = server;
    _publish();
    bool ok;
    try {
      ok = await probe(uri);
    } catch (_) {
      ok = false;
    }
    _connecting = null;
    if (ok) _selected = server;
    _publish();
    return ok;
  }

  void _onFound(List<DiscoveredServer> found) {
    _loaded = true;
    _error = null;
    _available = [for (final s in found) ServerOption.fromDiscovered(s)];
    final selected = _selected;
    if (selected == null) {
      if (_available.isNotEmpty) {
        _selected = _available[_random.nextInt(_available.length)];
      }
    } else {
      final index = _available.indexOf(selected);
      // com o endereço mais novo, se mudou
      if (index >= 0) _selected = _available[index];
    }
    _publish();
  }

  void _onError(Object error, StackTrace stack) {
    _loaded = true;
    _error = error;
    _publish();
  }

  void _publish() {
    final selected = _selected;
    _current = ServerListState(
      available: _available,
      selected: selected,
      selectedConnected: selected != null && _available.contains(selected),
      searchError: _error,
      connecting: _connecting,
      loaded: _loaded,
    );
    if (!_out.isClosed) _out.add(_current);
  }

  /// Para a busca e fecha o stream.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _out.close();
  }
}
