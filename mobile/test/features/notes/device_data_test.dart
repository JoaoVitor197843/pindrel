import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/data/device_data.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pindrel_erase'));
  tearDown(() => dir.deleteSync(recursive: true));

  File put(String name) => File(p.join(dir.path, name))..writeAsStringSync('x');
  const id = '3f2a9c1e-0000-4000-8000-123456789abc';

  DeviceData data({Future<void> Function()? secure}) =>
      DeviceData(directory: () async => dir, clearSecure: secure ?? () async {}, secureTimeout: const Duration(milliseconds: 200));

  test('removes the databases (with SQLite side files) and the remembered-servers file, nothing else', () async {
    final gone = ['notes.db', 'notes.db-wal', 'notes.db-shm', 'notes-$id.db', 'notes-$id.db-journal', 'pindrel-store.json', 'pindrel-store.json.tmp'];
    final kept = ['notes.db.bak', 'notes-.db', 'photo.png', 'other.json'];
    for (final n in [...gone, ...kept]) {
      put(n);
    }
    Directory(p.join(dir.path, 'notes.db-dir')).createSync();
    final removed = await data().erase();
    expect(removed, gone.length);
    for (final n in gone) {
      expect(File(p.join(dir.path, n)).existsSync(), isFalse, reason: n);
    }
    for (final n in kept) {
      expect(File(p.join(dir.path, n)).existsSync(), isTrue, reason: '$n is not ours');
    }
    expect(Directory(p.join(dir.path, 'notes.db-dir')).existsSync(), isTrue);
  });

  test('empties the secure storage; a keyring that fails or never answers is not an error', () async {
    var cleared = 0;
    await data(secure: () async => cleared++).erase();
    expect(cleared, 1);
    await data(secure: () async => throw StateError('locked keyring')).erase();
    await data(secure: () => Future<void>.delayed(const Duration(hours: 1))).erase(); // never answers: the time limit ends it
  });

  test('a folder that does not exist yet is fine, and erasing twice is too', () async {
    dir.deleteSync(recursive: true);
    expect(await data().erase(), 0);
    dir.createSync();
    put('notes.db');
    expect(await data().erase(), 1);
    expect(await data().erase(), 0);
  });

  test('owns() takes only the app\'s own names, whatever the folder holds', () {
    for (final bad in ['', 'notes', 'notes.db.', '../notes.db', 'notes-abc.db', 'NOTES.DB', 'notes-$id.db.x', 'pindrel-store.json.bak', ' notes.db']) {
      expect(DeviceData.owns(bad), isFalse, reason: bad);
    }
    expect(DeviceData.owns('notes-$id.db-wal'), isTrue);
  });
}
