import 'discovered_server.dart';

/// The servers known right now, by name (the service name is unique on the network:
/// mDNS renames on conflict).
///
/// An mDNS announcement is anonymous and any device on the network can send as many
/// as it likes; that is why the table has a cap ([maxServers]) and refuses absurd names.
/// When it is full, what is already known wins: a new announcement is ignored and
/// never evicts an old server.
///
/// A server that stops being seen does not leave right away: Wi-Fi drops multicast packets
/// and a false "gone" is common. It is marked as lost
/// ([markLost]), stays in the list and is only removed by [expire] after being
/// lost for the whole tolerance period. Being seen again ([upsert]) clears the
/// mark. Both discoveries (nsd and Linux mDNS) use the same rules.
class ServerTable {
  ServerTable({this.maxServers = defaultMaxServers, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const defaultMaxServers = 64;
  /// How long a lost server stays in the list (nsd and Linux).
  static const defaultLostGrace = Duration(seconds: 15);
  static const maxNameLength = 64;
  static const maxHostLength = 253;

  final int maxServers;
  final DateTime Function() _clock;
  final Map<String, DiscoveredServer> _byName = {};
  final Map<String, DateTime> _lostSince = {};

  bool get isEmpty => _byName.isEmpty;

  /// Whether any server is marked as lost (and still in the list).
  bool get hasLost => _lostSince.isNotEmpty;

  /// Inserts or replaces (a re-announced server brings the newest address) and
  /// clears the lost mark. Returns whether anything visible changed; refused
  /// announcements (name or host too big, table full) change nothing.
  bool upsert(DiscoveredServer server) {
    if (server.name.length > maxNameLength ||
        server.host.length > maxHostLength) {
      return false;
    }
    final known = _byName.containsKey(server.name);
    if (!known && _byName.length >= maxServers) return false;
    _lostSince.remove(server.name);
    if (_byName[server.name] == server) return false;
    _byName[server.name] = server;
    return true;
  }

  /// Marks [name] as lost now; if it already was, keeps the earlier time.
  /// Returns whether the server existed.
  bool markLost(String name) {
    if (!_byName.containsKey(name)) return false;
    _lostSince.putIfAbsent(name, _clock);
    return true;
  }

  /// Removes the ones lost for [grace] or more. Returns whether it removed any.
  bool expire(Duration grace) {
    final now = _clock();
    final gone = [
      for (final e in _lostSince.entries)
        if (now.difference(e.value) >= grace) e.key,
    ];
    for (final name in gone) {
      _byName.remove(name);
      _lostSince.remove(name);
    }
    return gone.isNotEmpty;
  }

  /// Returns whether the server existed.
  bool remove(String name) {
    _lostSince.remove(name);
    return _byName.remove(name) != null;
  }

  /// Immutable list, sorted by name (case-insensitive).
  List<DiscoveredServer> get snapshot => List.unmodifiable(
    _byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );
}
