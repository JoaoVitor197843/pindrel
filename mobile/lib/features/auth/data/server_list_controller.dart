import 'dart:async';

import '../../../core/network/discovery/discovered_server.dart';
import '../../../core/network/discovery/server_discovery.dart';
import '../../../core/network/pairing.dart';
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
/// Nothing is chosen on its own: the person picks, and a server never opened before has to be paired first
/// (see `PairingFlow`). The servers already opened before, or paired, are marked as trusted.
///
/// The chosen server does not vanish when it leaves the network: it stays chosen and counts
/// as disconnected, and goes back to connected if announced again.
class ServerListController {
  ServerListController({
    required ServerDiscovery discovery,
    this.probe,
    ServerTrust? trust,
    PairedStore? paired,
    // ignore: prefer_initializing_formals
  }) : _trust = trust,
       // ignore: prefer_initializing_formals
       _paired = paired {
    _ready = _load();
    _subscription = discovery.watch().listen(_onFound, onError: _onError);
  }

  /// What the user opened before, by name; without it every server is trusted as before.
  final ServerTrust? _trust;

  /// The servers this device paired with (their CA is kept); the ones that are not on the network are still listed.
  final PairedStore? _paired;

  /// Paired servers the network does not announce (added by hand, or announced no more): they stay in the list.
  List<ServerOption> _manual = const [];
  List<ServerOption> _discovered = const [];

  /// What the device remembers, with a limit: secure storage that never answers must not keep the list from showing.
  static const loadTimeout = Duration(seconds: 3);

  Future<void> _load() async {
    try {
      await _trust?.load().timeout(loadTimeout);
    } catch (_) {
      // nothing remembered
    }
    try {
      final all = await _paired?.all().timeout(loadTimeout) ?? const <PairedServer>[];
      _manual = [for (final p in all) ServerOption.fromPaired(p)];
    } catch (_) {
      _manual = const [];
    }
  }

  /// Done once what was remembered has been read: nothing is decided before.
  late final Future<void> _ready;
  ServerOption? _pending;
  bool _disposed = false;

  /// Tests the server before choosing it; without it the choice is immediate.
  /// The server picked on its own at start goes through the same test.
  final ServerProbe? probe;

  bool _paused = false;
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

  /// The name was opened before, but with another id: it is not the server the person knows.
  bool isChanged(ServerOption server) =>
      _trust?.trustOf(server.name, server.serverId) == Trust.changed;

  /// Opened before with this very id (or paired): the person does not have to pair again.
  bool _isTrusted(String name, String id) =>
      _trust == null || _trust.trustOf(name, id) == Trust.same;

  ServerOption _withGivenName(ServerOption d) {
    for (final m in _manual) {
      if (m.id == d.id && m.name != m.trustName) return d.withName(m.name);
    }
    return d;
  }

  /// The list the screen shows: what the network announces, then the paired servers it does not.
  void _rebuild() {
    _available = [
      // an announced server the person has named keeps the name they gave it
      for (final d in _discovered) _withGivenName(d),
      for (final m in _manual)
        if (!_discovered.any((d) => d.id == m.id || d.address == m.address))
          m,
    ];
  }

  /// The person confirmed the digits (or typed them): [server] is paired and becomes the chosen one. Its name and id are
  /// remembered, so from now on it is trusted without asking again.
  Future<void> completePairing(ServerOption server) async {
    await _ready;
    final trusted = server.withTrusted(true);
    final trust = _trust;
    if (trust != null) await trust.remember(trusted.trustName, trusted.serverId);
    _manual = [
      for (final m in _manual)
        if (m.id != trusted.id) m,
      if (trusted.baseUri?.scheme == 'https') trusted,
    ];
    _discovered = [
      for (final d in _discovered) d.id == trusted.id ? d.withTrusted(true) : d,
    ];
    _rebuild();
    _pending = null;
    _selected = trusted;
    _publish();
  }

  void _onFound(List<DiscoveredServer> found) {
    // after what is remembered has been read, in the order the lists arrived
    _ready.then((_) {
      if (!_disposed) _handleFound(found);
    });
  }

  void _handleFound(List<DiscoveredServer> found) {
    _loaded = true;
    _error = null;
    _discovered = [
      for (final s in found)
        ServerOption.fromDiscovered(s).withTrusted(_isTrusted(s.name, s.id)),
    ];
    _rebuild();
    final selected = _selected;
    if (selected != null) {
      final index = _available.indexOf(selected);
      // with the newest address, if it changed
      if (index >= 0) _selected = _available[index];
    }
    _publish();
  }

  /// The app went to the background: the search stops (it costs RAM and battery) and
  /// the choice is kept.
  void pause() {
    if (_paused || _disposed) return;
    _paused = true;
    _subscription.pause();
  }

  /// The app is back: the search starts again.
  void resume() {
    if (!_paused || _disposed) return;
    _paused = false;
    _subscription.resume();
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
