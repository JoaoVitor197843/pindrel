import 'server_option.dart';

/// Situation of the chosen server relative to the network.
enum ServerConnection {
  /// No server chosen yet (nothing was found).
  none,

  /// The chosen server is being announced on the network right now.
  connected,

  /// The chosen server left the network. It stays chosen until the user
  /// switches or it comes back.
  disconnected,
}

/// What the login screen shows about the servers, all at once.
class ServerListState {
  const ServerListState({
    this.available = const [],
    this.selected,
    this.selectedConnected = false,
    this.searchError,
    this.connecting,
    this.pendingChange,
    this.loaded = false,
  });

  /// The servers the network announces right now.
  final List<ServerOption> available;

  /// The chosen server (drawn at random or picked by the user), whether or not it is on the network.
  final ServerOption? selected;

  final bool selectedConnected;

  /// Why the search failed (for example, no network permission), if it did.
  final Object? searchError;

  /// The server being tested before it is chosen, if any.
  final ServerOption? connecting;

  /// A server whose name the user has opened before but whose id is another one: waits for the user to say go on
  /// (`confirmChange`) or not (`cancelChange`).
  final ServerOption? pendingChange;

  /// Whether the search has answered at least once (with a list or with an error).
  final bool loaded;

  ServerConnection get connection {
    if (selected == null) return ServerConnection.none;
    return selectedConnected
        ? ServerConnection.connected
        : ServerConnection.disconnected;
  }

  /// The servers that are no longer on the network but still matter: the chosen one
  /// that left. Anyone not chosen disappears from the list when leaving.
  List<ServerOption> get disconnected =>
      connection == ServerConnection.disconnected ? [selected!] : const [];
}
