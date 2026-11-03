import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/discovery/platform_discovery.dart';
import '../../../../core/network/discovery/server_discovery.dart';
import '../../../../core/network/pairing.dart';
import '../../../../core/network/server_probe.dart';
import '../../../../core/network/server_security.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/durable_store.dart';
import '../../data/secure_paired_store.dart';
import '../../data/server_list_controller.dart';
import '../../data/server_trust.dart';

/// How servers are looked for on the network. Tests swap it for a fake
/// discovery.
final serverDiscoveryProvider = Provider<ServerDiscovery>(
  (ref) => createPlatformDiscovery(),
);

/// How a server is tested before being chosen. Tests swap it for a fake
/// function.
final serverProbeProvider = Provider<ServerProbe>((ref) => httpServerProbe);

/// Where what the device remembers lives: the secure storage, and a file of the app's own when that does not work (a Linux
/// keyring that is locked). Tests swap it for a memory store.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => DurableKeyValueStore(
    const SecureKeyValueStore(FlutterSecureStorage(), true),
    FileKeyValueStore(getApplicationSupportDirectory),
  ),
);

/// Where the servers the user opened are remembered.
final serverTrustProvider = Provider<ServerTrust>(
  (ref) => ServerTrust(ref.watch(keyValueStoreProvider)),
);

/// Where the servers this device paired with are kept (their CA, trusted for that server only).
final pairedStoreProvider = Provider<PairedStore>(
  (ref) => SecurePairedStore(ref.watch(keyValueStoreProvider)),
);

/// How a server's TLS port is found, and how the digits pairing runs. Tests swap them for fakes.
final tlsOfferProvider = Provider<Future<TlsOffer?> Function(Uri)>(
  (ref) => (base) => fetchTlsOffer(base),
);
final digitsPairerProvider = Provider<DigitsPairer>((ref) => pairWithDigits);

/// The login screen's server list: the available ones, the chosen one and whether it
/// is still on the network. The screen follows it with a `StreamBuilder` on
/// `controller.stream`. The network search lasts as long as the controller exists.
final serverListControllerProvider = Provider<ServerListController>((ref) {
  final controller = ServerListController(
    discovery: ref.watch(serverDiscoveryProvider),
    probe: ref.watch(serverProbeProvider),
    trust: ref.watch(serverTrustProvider),
    paired: ref.watch(pairedStoreProvider),
  );
  final lifecycle = _SearchLifecycle(controller);
  WidgetsFlutterBinding.ensureInitialized().addObserver(lifecycle);
  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(lifecycle);
    controller.dispose();
  });
  return controller;
});

/// Stops the network search while the app is in the background and starts it again
/// when it is back. Only `paused`/`hidden` count: `inactive` also happens with a
/// permission dialog or the notification shade on top, where the search must go on.
class _SearchLifecycle with WidgetsBindingObserver {
  _SearchLifecycle(this._controller);

  final ServerListController _controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _controller.pause();
      case AppLifecycleState.resumed:
        _controller.resume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }
}
