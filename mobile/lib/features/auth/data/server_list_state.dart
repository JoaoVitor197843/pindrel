import 'server_option.dart';

/// Situação do servidor escolhido em relação à rede.
enum ServerConnection {
  /// Nenhum servidor escolhido ainda (nada foi achado).
  none,

  /// O servidor escolhido está sendo anunciado na rede agora.
  connected,

  /// O servidor escolhido saiu da rede. Continua escolhido até o usuário
  /// trocar ou ele voltar.
  disconnected,
}

/// O que a tela de login mostra sobre os servidores, de uma vez só.
class ServerListState {
  const ServerListState({
    this.available = const [],
    this.selected,
    this.selectedConnected = false,
    this.searchError,
    this.connecting,
    this.loaded = false,
  });

  /// Os servidores que a rede anuncia agora.
  final List<ServerOption> available;

  /// O servidor escolhido (sorteado ou pelo usuário), esteja ele na rede ou não.
  final ServerOption? selected;

  final bool selectedConnected;

  /// Por que a busca falhou (por exemplo, sem permissão de rede), se falhou.
  final Object? searchError;

  /// O servidor que está sendo testado antes de ser escolhido, se houver.
  final ServerOption? connecting;

  /// Se a busca já respondeu pelo menos uma vez (com lista ou com erro).
  final bool loaded;

  ServerConnection get connection {
    if (selected == null) return ServerConnection.none;
    return selectedConnected
        ? ServerConnection.connected
        : ServerConnection.disconnected;
  }

  /// Os servidores que já não estão na rede mas ainda interessam: o escolhido
  /// que saiu. Quem não está escolhido some da lista ao sair.
  List<ServerOption> get disconnected =>
      connection == ServerConnection.disconnected ? [selected!] : const [];
}
