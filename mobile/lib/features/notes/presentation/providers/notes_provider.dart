import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/notes_db.dart';
import '../../data/workspace.dart';

/// The notes of this device. Opened once, from a file in the app's support
/// folder; tests replace it with a workspace over an in-memory database.
final workspaceProvider = FutureProvider<Workspace>((ref) async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = NotesDb.open(p.join(dir.path, 'notes.db'));
  final ws = Workspace(db);
  ref.onDispose(ws.dispose);
  return ws;
});

final _accountId = RegExp(r'^[0-9a-fA-F-]{8,64}$');

/// The notes of a signed-in account: their own database file, so another account (or the notes of the device) never
/// shares one. The id comes from the server, so it is checked before it becomes part of a file name.
final accountWorkspaceProvider = FutureProvider.autoDispose.family<Workspace, String>((ref, accountId) async {
  if (!_accountId.hasMatch(accountId)) throw ArgumentError('invalid account id');
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final ws = Workspace(NotesDb.open(p.join(dir.path, 'notes-$accountId.db')));
  ref.onDispose(ws.dispose);
  return ws;
});
