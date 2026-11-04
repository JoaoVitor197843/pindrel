import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'server_trust.dart';

/// A small JSON file in the app's own folder, for what the secure storage cannot keep (a Linux session whose keyring is
/// locked, or has none). It is what the servers this device paired with are made of: public certificates and names, nothing
/// secret, so a file the user alone can read is enough. Writes are queued and atomic (a temporary file, then a rename).
class FileKeyValueStore implements KeyValueStore {
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
  Future<void> write(String key, String value) {
    final done = _queue.then((_) async {
      final data = await _load()..[key] = value;
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
      return;
    } catch (_) {
      // the keyring is locked, missing or silent: the file keeps it
    }
    try {
      await fallback.write(key, value);
    } catch (_) {
      // nothing can keep it; it lives for this session only
    }
  }
}
