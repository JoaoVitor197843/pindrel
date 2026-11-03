import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the servers the user has opened are kept between runs.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

/// On the device's secure storage. By default a device where it does not work (no keyring) simply remembers nothing; with
/// [throwOnError] the failure is passed on, so something else (see `DurableKeyValueStore`) can take over.
class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore([this._storage = const FlutterSecureStorage(), this.throwOnError = false]);

  final FlutterSecureStorage _storage;
  final bool throwOnError;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      if (throwOnError) rethrow;
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      if (throwOnError) rethrow;
      // nothing is remembered; nobody is warned, which is how it was
    }
  }
}

/// What a name meant the last time the user opened it.
enum Trust {
  /// Never opened (or opened when it had no id).
  unknown,

  /// The id it had.
  same,

  /// Another id under the same name, or none where there was one: a server does not lose its id, an imitation of it
  /// never had it.
  changed,
}

/// Which server was behind each name when the user opened it. An announcement is anonymous: anyone on the network can
/// call themselves "Casa". The id the real server keeps is what lets us notice that the one answering now is not
/// the one opened before. Kept on the device only.
class ServerTrust {
  ServerTrust(this._store);

  static const storageKey = 'pindrel.servers';
  static const maxRemembered = 64;

  final KeyValueStore _store;

  /// Oldest first, so the oldest goes when the list is full.
  List<(String, String)> _entries = [];

  /// Reads what was remembered. Anything damaged is ignored.
  Future<void> load() async {
    try {
      final raw = await _store.read(storageKey);
      final parsed = raw == null ? null : jsonDecode(raw);
      if (parsed is! List) return;
      final entries = <(String, String)>[
        for (final e in parsed)
          if (e is List && e.length == 2 && e[0] is String && e[1] is String)
            (e[0] as String, e[1] as String),
      ];
      _entries = entries.length > maxRemembered
          ? entries.sublist(entries.length - maxRemembered)
          : entries;
    } catch (_) {
      _entries = [];
    }
  }

  Trust trustOf(String name, String id) {
    final known = _entries.where((e) => e.$1 == name).firstOrNull;
    if (known == null) return Trust.unknown;
    if (known.$2.isEmpty) return id.isEmpty ? Trust.same : Trust.unknown;
    return known.$2 == id ? Trust.same : Trust.changed;
  }

  Future<void> remember(String name, String id) async {
    _entries = [..._entries.where((e) => e.$1 != name), (name, id)];
    if (_entries.length > maxRemembered) {
      _entries = _entries.sublist(_entries.length - maxRemembered);
    }
    try {
      await _store.write(
        storageKey,
        jsonEncode([
          for (final e in _entries) [e.$1, e.$2],
        ]),
      );
    } catch (_) {
      // not saved: it is only remembered for this session, and nobody is warned, which is how it was
    }
  }
}
