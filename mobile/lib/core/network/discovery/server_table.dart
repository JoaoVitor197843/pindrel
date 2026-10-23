import 'discovered_server.dart';

/// Os servidores conhecidos agora, por nome (o nome do serviço é único na rede:
/// o mDNS renomeia em caso de conflito).
///
/// Um anúncio mDNS é anônimo e qualquer aparelho da rede pode mandar quantos
/// quiser; por isso a tabela tem teto ([maxServers]) e recusa nomes absurdos.
/// Quando está cheia, o que já é conhecido ganha: um anúncio novo é ignorado,
/// nunca expulsa um servidor antigo.
///
/// Um servidor que deixa de ser visto não sai na hora: o Wi-Fi perde pacotes
/// multicast e um "sumiu" falso é comum. Ele é marcado como perdido
/// ([markLost]), segue na lista e só é removido por [expire] depois de ficar
/// perdido por todo o prazo de tolerância. Ser visto de novo ([upsert]) apaga a
/// marca. As duas descobertas (nsd e mDNS do Linux) usam as mesmas regras.
class ServerTable {
  ServerTable({this.maxServers = defaultMaxServers, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const defaultMaxServers = 64;
  /// Quanto tempo um servidor perdido continua na lista (nsd e Linux).
  static const defaultLostGrace = Duration(seconds: 15);
  static const maxNameLength = 64;
  static const maxHostLength = 253;

  final int maxServers;
  final DateTime Function() _clock;
  final Map<String, DiscoveredServer> _byName = {};
  final Map<String, DateTime> _lostSince = {};

  bool get isEmpty => _byName.isEmpty;

  /// Se algum servidor está marcado como perdido (e ainda na lista).
  bool get hasLost => _lostSince.isNotEmpty;

  /// Insere ou substitui (um servidor reanunciado traz o endereço mais novo) e
  /// apaga a marca de perdido. Devolve se algo visível mudou; anúncios
  /// recusados (nome ou host grande demais, tabela cheia) não mudam nada.
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

  /// Marca [name] como perdido agora; se já estava, mantém a hora de antes.
  /// Devolve se havia o servidor.
  bool markLost(String name) {
    if (!_byName.containsKey(name)) return false;
    _lostSince.putIfAbsent(name, _clock);
    return true;
  }

  /// Remove os perdidos há [grace] ou mais. Devolve se removeu algum.
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

  /// Devolve se havia o servidor.
  bool remove(String name) {
    _lostSince.remove(name);
    return _byName.remove(name) != null;
  }

  /// Lista imutável, ordenada por nome (sem diferenciar maiúsculas).
  List<DiscoveredServer> get snapshot => List.unmodifiable(
    _byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );
}
