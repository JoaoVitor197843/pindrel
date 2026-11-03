import 'dart:convert';

import '../../../core/network/pairing.dart';
import 'server_trust.dart';

/// Where the paired servers (their CA, kept only for that server) live between runs: the device's secure storage.
class SecurePairedStore implements PairedStore {
  SecurePairedStore(this._store);

  static const storageKey = 'pindrel.paired';
  static const maxPaired = 64;

  final KeyValueStore _store;

  Future<List<PairedServer>> _read() async {
    try {
      final raw = await _store.read(storageKey);
      final parsed = raw == null ? null : jsonDecode(raw);
      if (parsed is! List) return [];
      // an entry that does not check out (its CA is not the one it names) is dropped, not trusted
      return [
        for (final e in parsed)
          ?PairedServer.fromJson(e),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<PairedServer> items) async {
    await _store.write(storageKey, jsonEncode([for (final i in items) i.toJson()]));
  }

  @override
  Future<List<PairedServer>> all() => _read();

  @override
  Future<PairedServer?> find(String hostPort) async => (await _read()).where((p) => p.hostPort == hostPort).firstOrNull;

  @override
  Future<void> save(PairedServer server) async {
    final items = [for (final p in await _read()) if (p.hostPort != server.hostPort) p, server];
    await _write(items.length > maxPaired ? items.sublist(items.length - maxPaired) : items);
  }

  @override
  Future<void> forget(String hostPort) async => _write([for (final p in await _read()) if (p.hostPort != hostPort) p]);
}
