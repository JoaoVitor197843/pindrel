import 'dart:async';
import 'dart:math';

import '../../../core/network/discovery/discovered_server.dart';
import '../../../core/network/discovery/server_discovery.dart';
import '../../../core/network/server_probe.dart';
import 'server_list_state.dart';
import 'server_option.dart';

/// Joins server discovery with the user's choice and delivers the
/// result as a [Stream] of [ServerListState], which the screen consumes with
/// `StreamBuilder`.
///
/// Discovery is subscribed to only once, here; whoever wants to follow the list
/// (button, open menu, footer) subscribes to [stream], which accepts many listeners.
///
/// The chosen server does not vanish when it leaves the network: it stays chosen and counts
/// as disconnected, and goes back to connected if announced again.
class ServerListController {
  ServerListController({
    required ServerDiscovery discovery,
    Random? random,
    this.probe,
  }) : _random = random ?? Random() {
    _subscription = discovery.watch().listen(_onFound, onError: _onError);
  }

  final Random _random;

  /// Tests the server before choosing it; without it the choice is immediate.
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

  /// The current state (for the `StreamBuilder`'s `initialData`).
  ServerListState get current => _current;

  /// Emits the new state on every change.
  Stream<ServerListState> get stream => _out.stream;

  /// The user chose [server] (an available one, or the disconnected one that was already
  /// chosen). A new server is tested first ([ServerListState.connecting]
  /// while it waits); if it does not respond, the previous choice stays and this returns false.
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
      // with the newest address, if it changed
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

  Future<void> dispose() async {
    await _subscription.cancel();
    await _out.close();
  }
}
