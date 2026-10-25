import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/discovery/platform_discovery.dart';
import '../../../../core/network/discovery/server_discovery.dart';
import '../../../../core/network/server_probe.dart';
import '../../data/server_list_controller.dart';
import '../../data/server_trust.dart';

/// How servers are looked for on the network. Tests swap it for a fake
/// discovery.
final serverDiscoveryProvider = Provider<ServerDiscovery>(
  (ref) => createPlatformDiscovery(),
);

/// Draw for the initial choice; tests pin the result.
final randomProvider = Provider<Random>((ref) => Random());

/// How a server is tested before being chosen. Tests swap it for a fake
/// function.
final serverProbeProvider = Provider<ServerProbe>((ref) => httpServerProbe);

/// Where the servers the user opened are remembered. Tests swap it for a memory store.
final serverTrustProvider = Provider<ServerTrust>(
  (ref) => ServerTrust(const SecureKeyValueStore()),
);

/// The login screen's server list: the available ones, the chosen one and whether it
/// is still on the network. The screen follows it with a `StreamBuilder` on
/// `controller.stream`. The network search lasts as long as the controller exists.
final serverListControllerProvider = Provider<ServerListController>((ref) {
  final controller = ServerListController(
    discovery: ref.watch(serverDiscoveryProvider),
    random: ref.watch(randomProvider),
    probe: ref.watch(serverProbeProvider),
    trust: ref.watch(serverTrustProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
