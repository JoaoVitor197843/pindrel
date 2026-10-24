import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/discovery/platform_discovery.dart';
import '../../../../core/network/discovery/server_discovery.dart';
import '../../../../core/network/server_probe.dart';
import '../../data/server_list_controller.dart';

/// Como os servidores são procurados na rede. Os testes trocam por uma
/// descoberta falsa.
final serverDiscoveryProvider = Provider<ServerDiscovery>(
  (ref) => createPlatformDiscovery(),
);

/// Sorteio da escolha inicial; os testes fixam o resultado.
final randomProvider = Provider<Random>((ref) => Random());

/// Como um servidor é testado antes de ser escolhido. Os testes trocam por uma
/// função falsa.
final serverProbeProvider = Provider<ServerProbe>((ref) => httpServerProbe);

/// A lista de servidores da tela de login: os disponíveis, o escolhido e se ele
/// ainda está na rede. A tela a acompanha com `StreamBuilder` em
/// `controller.stream`. A busca na rede dura enquanto o controlador existir.
final serverListControllerProvider = Provider<ServerListController>((ref) {
  final controller = ServerListController(
    discovery: ref.watch(serverDiscoveryProvider),
    random: ref.watch(randomProvider),
    probe: ref.watch(serverProbeProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
