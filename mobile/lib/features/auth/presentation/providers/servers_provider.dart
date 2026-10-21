import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/server_option.dart';

// TODO: substituir pelos servidores descobertos via mDNS (_plany._tcp).
const _mockServers = [
  ServerOption(id: 'casa', name: 'Casa', address: 'plany.casa.local'),
  ServerOption(id: 'escritorio', name: 'Escritório', address: '192.168.0.20'),
  ServerOption(id: 'nuvem', name: 'Nuvem', address: 'notas.exemplo.com'),
];

final serversProvider = Provider<List<ServerOption>>((ref) => _mockServers);

class SelectedServerNotifier extends Notifier<ServerOption> {
  @override
  ServerOption build() => ref.watch(serversProvider).first;

  void select(ServerOption server) => state = server;
}

final selectedServerProvider =
    NotifierProvider<SelectedServerNotifier, ServerOption>(
      SelectedServerNotifier.new,
    );
