import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'server_trust.dart';

/// A store that can drop a key.
abstract interface class RemovableStore {
  Future<void> remove(String key);
}

/// A small JSON file in the app's own folder, for what the secure storage cannot keep (a Linux session whose keyring is
/// locked, or has none). Mostly the servers this device paired with (public certificates and names), but also the note of
/// a session kept with "Manter conectado", refresh cookie included, when the keyring failed: so a file only the user can
/// read, and a copy the keyring took over is removed (`DurableKeyValueStore.write`). Writes are queued and atomic.
class FileKeyValueStore implements KeyValueStore, RemovableStore {
  FileKeyValueStore(this._directory, {this.fileName = 'pindrel-store.json'});

  final Future<Directory> Function() _directory;
  final String fileName;
  Future<void> _queue = Future<void>.value();

  Future<File> _file() async => File('${(await _directory()).path}${Platform.pathSeparator}$fileName');

  Future<Map<String, String>> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final parsed = jsonDecode(await file.readAsString());
      if (parsed is! Map) return {};
      return {
        for (final e in parsed.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      };
    } catch (_) {
      return {}; // damaged: starts over rather than failing
    }
  }

  @override
  Future<String?> read(String key) async {
    await _queue; // after any write that was asked for before
    return (await _load())[key];
  }

  @override
  Future<void> write(String key, String value) => _change((data) {
    data[key] = value;
    return true;
  });

  @override
  Future<void> remove(String key) => _change((data) => data.remove(key) != null);

  /// Applies [edit] and writes the file when it says something changed.
  Future<void> _change(bool Function(Map<String, String> data) edit) {
    final done = _queue.then((_) async {
      final data = await _load();
      if (!edit(data)) return;
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(data), flush: true);
      if (!Platform.isWindows) {
        // only its owner reads it; the folder is the app's own, this is a second lock
        await Process.run('chmod', ['600', temp.path]).catchError((_) => ProcessResult(0, 1, '', ''));
      }
      await temp.rename(file.path);
    });
    // one failed write must not poison the ones after it
    _queue = done.catchError((_) {});
    return done;
  }
}

/// The secure storage first, a file when it does not work. "Does not work" includes never answering (a keyring that waits
/// for an unlock nobody sees), so each try has a time limit.
class DurableKeyValueStore implements KeyValueStore {
  DurableKeyValueStore(this.primary, this.fallback, {this.primaryTimeout = const Duration(seconds: 4)});

  final KeyValueStore primary;
  final KeyValueStore fallback;
  final Duration primaryTimeout;

  @override
  Future<String?> read(String key) async {
    try {
      final value = await primary.read(key).timeout(primaryTimeout);
      if (value != null) return value;
    } catch (_) {
      // falls through to the file
    }
    try {
      return await fallback.read(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await primary.write(key, value).timeout(primaryTimeout);
    } catch (_) {
      await _toFallback(key, value);
      return;
    }
    // a copy the file kept while the keyring failed (a session note with its cookie) must not outlive it in clear
    if (fallback case final RemovableStore file) {
      try {
        await file.remove(key);
      } catch (_) {
        // best effort: the keyring holds the current value either way
      }
    }
  }

  /// The keyring is locked, missing or silent: the file keeps it.
  Future<void> _toFallback(String key, String value) async {
    try {
      await fallback.write(key, value);
    } catch (_) {
      // nothing can keep it; it lives for this session only
    }
  }
}
