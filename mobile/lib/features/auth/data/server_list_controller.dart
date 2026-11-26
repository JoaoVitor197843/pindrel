import 'dart:async';

import '../../../core/network/discovery/discovered_server.dart';
import '../../../core/network/discovery/server_discovery.dart';
import '../../../core/network/pairing.dart';
import '../../../core/network/server_probe.dart';
import 'server_list_state.dart';
import 'server_option.dart';
import 'server_trust.dart';

/// Why the network search is stopped.
enum SearchPause {
  /// The app is in the background.
  background,

  /// No screen shows the list (the login was left for the notes): searching would only cost CPU, battery and sockets.
  unwatched,
}

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
    this._trust,
    this._paired,
  }) {
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
  /// What answers after it still counts (`_takeLate`): the durable store falls back to its file only after its own
  /// limit (4 s), so on a Linux session with a silent keyring the paired servers arrive after this one.
  static const loadTimeout = Duration(seconds: 3);

  Future<void> _load() async {
    // both at once, so the wait is one limit and not two; a store that fails counts as remembering nothing (handled
    // here, at once: an error nobody listens to yet would surface as unhandled)
    final trust = _trust?.load().catchError((Object _) {});
    final paired = _paired?.all().then<List<PairedServer>>((all) => all, onError: (Object _) => const <PairedServer>[]);
    var late = false;
    try {
      await trust?.timeout(loadTimeout);
    } on TimeoutException {
      late = true;
    }
    try {
      final all = await paired?.timeout(loadTimeout) ?? const <PairedServer>[];
      _manual = [for (final p in all) ServerOption.fromPaired(p)];
    } on TimeoutException {
      _manual = const [];
      late = true;
    }
    if (late) _takeLate(trust, paired);
  }

  void _takeLate(Future<void>? trust, Future<List<PairedServer>>? paired) {
    Future.wait<void>([
      ?trust,
      if (paired != null)
        paired.then((all) {
          final loaded = [for (final p in all) ServerOption.fromPaired(p)];
          // a pairing completed meanwhile stays
          _manual = [
            ...loaded,
            for (final m in _manual)
              if (!loaded.any((l) => l.id == m.id)) m,
          ];
        }),
    ]).then((_) {
      if (_disposed) return;
      _discovered = [for (final d in _discovered) d.withTrusted(_isTrusted(d.trustName, d.serverId))];
      _rebuild();
      _publish();
    });
  }

  /// Done once what was remembered has been read: nothing is decided before.
  late final Future<void> _ready;
  ServerOption? _pending;
  bool _disposed = false;

  /// Tests the server before choosing it; without it the choice is immediate.
  /// The server picked on its own at start goes through the same test.
  final ServerProbe? probe;

  final Set<SearchPause> _pausedBy = {};
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

  /// An announced server this device paired with is reached the paired way: over HTTPS, at the address paired, with its
  /// pinned CA. The announcement carries the plain HTTP address, and it used to replace the paired entry, so the login
  /// went in clear and the pinned CA was never used.
  ServerOption _asPaired(ServerOption d) {
    for (final m in _manual) {
      final sameServer = m.serverId.isEmpty || d.serverId.isEmpty || m.serverId == d.serverId;
      if (m.id == d.id && sameServer && m.baseUri?.scheme == 'https') {
        return ServerOption(
          id: d.id,
          name: m.name,
          trustName: m.trustName,
          address: m.address,
          baseUri: m.baseUri,
          serverId: d.serverId.isNotEmpty ? d.serverId : m.serverId,
          trusted: true,
        );
      }
    }
    // an announced server the person has named keeps the name they gave it
    return _withGivenName(d);
  }

  /// The list the screen shows: what the network announces, then the paired servers it does not.
  void _rebuild() {
    _available = [
      for (final d in _discovered) _asPaired(d),
      for (final m in _manual)
        if (!_discovered.any((d) => d.id == m.id || d.address == m.address))
          m,
    ];
  }

  /// The person no longer trusts [server] (one they paired, opened before, or added by hand, announced or not). Its pairing
  /// and what was remembered about it are forgotten; if it was the chosen one it is not any more. An announced server stays
  /// in the list as a new one, so it can be paired again; one only known from the pairing disappears.
  Future<void> revokeTrust(ServerOption server) async {
    await _ready;
    await _trust?.forget(server.trustName);
    final paired = _paired;
    if (paired != null) {
      try {
        for (final p in await paired.all()) {
          if (ServerOption.idFor(p.name) == server.id &&
              (server.serverId.isEmpty || p.serverId.isEmpty || p.serverId == server.serverId)) {
            await paired.forget(p.hostPort);
          }
        }
      } catch (_) {
        // the list below is what the person sees; a store that fails cannot keep it trusted this session
      }
    }
    _manual = [
      for (final m in _manual)
        if (m.id != server.id) m,
    ];
    _discovered = [
      for (final d in _discovered) d.id == server.id ? d.withTrusted(false) : d,
    ];
    _rebuild();
    if (_selected != null && _selected!.id == server.id) _selected = null;
    if (_pending?.id == server.id) _pending = null;
    _publish();
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
      // with the newest address, if it changed; but a choice reached over HTTPS never falls back to plain HTTP
      if (index >= 0 && !(selected.baseUri?.scheme == 'https' && _available[index].baseUri?.scheme != 'https')) {
        _selected = _available[index];
      }
    }
    _publish();
  }

  /// The app went to the background: the search stops (it costs RAM and battery) and
  /// the choice is kept.
  void pause() => pauseFor(SearchPause.background);

  /// The app is back: the search starts again, unless something else still holds it.
  void resume() => resumeFor(SearchPause.background);

  /// Stops the search for [reason]. It runs again only when every reason is gone: an app that comes back from the
  /// background must not restart a search no screen shows.
  void pauseFor(SearchPause reason) {
    if (_disposed || !_pausedBy.add(reason) || _pausedBy.length > 1) return;
    _subscription.pause();
  }

  void resumeFor(SearchPause reason) {
    if (_disposed || !_pausedBy.remove(reason) || _pausedBy.isNotEmpty) return;
    _subscription.resume();
  }

  /// Whether the network is being searched now.
  bool get searching => _pausedBy.isEmpty && !_disposed;

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
