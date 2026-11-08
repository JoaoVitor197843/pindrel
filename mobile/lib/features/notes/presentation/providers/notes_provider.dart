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
