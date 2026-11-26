import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/data/server_trust.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/device_data.dart';
import '../../data/notes_db.dart';
import '../../data/workspace.dart';

/// The notes of this device. Opened once, from a file in the app's support
/// folder; tests replace it with a workspace over an in-memory database.
/// Every notes database that is open now (the device's and the accounts'). Erasing the device closes them all first:
/// a provider that is invalidated while a screen still watches it opens its file again at once, and an account's
/// lives until its screen is disposed, so on Windows (where an open file cannot be deleted) the notes stayed behind.
final openWorkspacesProvider = Provider<Set<Workspace>>((ref) => <Workspace>{});

/// Registers [ws] as open for as long as the provider that made it lives (tests build their own the same way).
Workspace trackedWorkspace(Ref ref, Workspace ws) {
  final open = ref.read(openWorkspacesProvider)..add(ws);
  ref.onDispose(() {
    open.remove(ws);
    ws.dispose();
  });
  return ws;
}

final workspaceProvider = FutureProvider<Workspace>((ref) async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  return trackedWorkspace(ref, Workspace(NotesDb.open(p.join(dir.path, 'notes.db'))));
});

final _accountId = RegExp(r'^[0-9a-fA-F-]{8,64}$');

/// The notes of a signed-in account: their own database file, so another account (or the notes of the device) never
/// shares one. The id comes from the server, so it is checked before it becomes part of a file name.
final accountWorkspaceProvider = FutureProvider.autoDispose.family<Workspace, String>((ref, accountId) async {
  if (!_accountId.hasMatch(accountId)) throw ArgumentError('invalid account id');
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  return trackedWorkspace(ref, Workspace(NotesDb.open(p.join(dir.path, 'notes-$accountId.db'))));
});

/// What can be erased from this device. Tests replace it with a temporary folder.
final deviceDataProvider = Provider<DeviceData>(
  (ref) => DeviceData(directory: getApplicationSupportDirectory, clearSecure: () => appSecureStorage.deleteAll()),
);
