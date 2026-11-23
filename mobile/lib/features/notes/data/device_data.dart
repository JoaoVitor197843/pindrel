import 'dart:async';
import 'dart:io';

/// Everything the app keeps on this device, so the person can erase it without uninstalling: the notes databases (the
/// device's own and one per account), the file of what the device remembers and whatever the secure storage holds
/// (the session, the paired servers). Nothing on any server is touched.
class DeviceData {
  DeviceData({required this.directory, required this.clearSecure, this.secureTimeout = const Duration(seconds: 4)});

  /// The app's support folder.
  final Future<Directory> Function() directory;

  /// Empties the secure storage.
  final Future<void> Function() clearSecure;
  final Duration secureTimeout;

  // Only names the app itself writes are removed (the databases with SQLite's side files, and the remembered-servers file
  // with its temporary copy): the folder is the app's own, but a file nobody here made is not ours to delete.
  static final _owned = RegExp(r'^(notes(-[0-9a-fA-F-]{8,64})?\.db(-wal|-shm|-journal)?|pindrel-store\.json(\.tmp)?)$');

  static bool owns(String fileName) => _owned.hasMatch(fileName);

  /// Closes nothing: whoever holds a database open must have closed it already (Windows refuses to delete an open file).
  /// Returns how many files went. A file that cannot be deleted throws, after the others were tried.
  Future<int> erase() async {
    var removed = 0;
    Object? failure;
    final dir = await directory();
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!owns(name)) continue;
        try {
          await entry.delete();
          removed++;
        } catch (e) {
          failure ??= e;
        }
      }
    }
    try {
      // a keyring that is locked or missing keeps nothing of ours, so a refusal here is not a failure
      await clearSecure().timeout(secureTimeout);
    } catch (_) {}
    if (failure != null) throw failure;
    return removed;
  }
}
