import 'discovered_server.dart';

/// Looks for Pindrel servers on the local network.
abstract interface class ServerDiscovery {
  /// Emits the complete list of known servers on every change (the
  /// first one, empty, right on subscription). The search starts on subscribe and ends on
  /// cancel. An error (for example, no network permission) comes out as a stream
  /// error.
  Stream<List<DiscoveredServer>> watch();
}

/// For platforms without mDNS (web): never finds anything.
class NoDiscovery implements ServerDiscovery {
  const NoDiscovery();

  @override
  Stream<List<DiscoveredServer>> watch() =>
      Stream.value(const <DiscoveredServer>[]);
}
