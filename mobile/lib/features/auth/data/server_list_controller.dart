import 'dart:async';
import 'dart:math';

import '../../../core/network/discovery/discovered_server.dart';
import '../../../core/network/discovery/server_discovery.dart';
import '../../../core/network/server_probe.dart';
import 'server_list_state.dart';
import 'server_option.dart';
import 'server_trust.dart';

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
    ServerTrust? trust,
  }) : _random = random ?? Random(),
       _trust = trust {
    _ready = trust?.load() ?? Future<void>.value();
    _subscription = discovery.watch().listen(_onFound, onError: _onError);
  }

  /// What the user opened before, by name; without it every server is trusted as before.
  final ServerTrust? _trust;

  /// Done once what was remembered has been read: nothing is decided before.
  late final Future<void> _ready;
  ServerOption? _pending;
  bool _disposed = false;

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
  ///
  /// A server whose name was opened before with another id is not opened at once: it becomes
  /// [ServerListState.pendingChange] and this returns true (nothing failed); [confirmChange] goes on.
  Future<bool> select(ServerOption server, {bool confirmed = false}) async {
    final trust = _trust;
    if (trust != null) {
      await _ready;
      if (!confirmed && server != _selected) {
        if (_pending != null) return true; // the question is still open
        if (trust.trustOf(server.name, server.serverId) == Trust.changed) {
          _pending = server;
          _publish();
          return true;
        }
      }
    }
    _pending = null;
    final probe = this.probe;
    final uri = server.baseUri;
    if (probe == null || uri == null || server == _selected) {
      _choose(server);
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
    if (ok) _choose(server);
    _publish();
    return ok;
  }

  /// The user accepted the change: goes on to the server.
  Future<bool> confirmChange() async {
    final server = _pending;
    return server == null ? true : select(server, confirmed: true);
  }

  void cancelChange() {
    if (_pending == null) return;
    _pending = null;
    _publish();
  }

  /// Only what was really chosen becomes the server the user knows.
  void _choose(ServerOption server) {
    _selected = server;
    final trust = _trust;
    if (trust != null) unawaited(trust.remember(server.name, server.serverId));
  }

  void _onFound(List<DiscoveredServer> found) {
    if (_trust == null) return _handleFound(found);
    // after what is remembered has been read, in the order the lists arrived
    _ready.then((_) {
      if (!_disposed) _handleFound(found);
    });
  }

  void _handleFound(List<DiscoveredServer> found) {
    _loaded = true;
    _error = null;
    _available = [for (final s in found) ServerOption.fromDiscovered(s)];
    final selected = _selected;
    if (selected == null) {
      // a name that now answers with another id than the one opened before is never picked on its own
      final trust = _trust;
      final candidates = [
        for (final s in _available)
          if (trust == null ||
              trust.trustOf(s.name, s.serverId) != Trust.changed)
            s,
      ];
      if (candidates.isNotEmpty) {
        _choose(candidates[_random.nextInt(candidates.length)]);
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
      pendingChange: _pending,
      loaded: _loaded,
    );
    if (!_out.isClosed) _out.add(_current);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription.cancel();
    await _out.close();
  }
}
