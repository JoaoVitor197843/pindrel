import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/discovery/platform_discovery.dart';
import '../../../../core/network/discovery/server_discovery.dart';
import '../../data/server_list_controller.dart';

/// Como os servidores são procurados na rede. Os testes trocam por uma
/// descoberta falsa.
final serverDiscoveryProvider = Provider<ServerDiscovery>(
  (ref) => createPlatformDiscovery(),
);

/// Sorteio da escolha inicial; os testes fixam o resultado.
final randomProvider = Provider<Random>((ref) => Random());

/// A lista de servidores da tela de login: os disponíveis, o escolhido e se ele
/// ainda está na rede. A tela a acompanha com `StreamBuilder` em
/// `controller.stream`. A busca na rede dura enquanto o controlador existir.
final serverListControllerProvider = Provider<ServerListController>((ref) {
  final controller = ServerListController(
    discovery: ref.watch(serverDiscoveryProvider),
    random: ref.watch(randomProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
