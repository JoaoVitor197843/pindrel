import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/data/durable_store.dart';
import 'package:mobile/features/auth/data/server_trust.dart';

class _Broken implements KeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('KeyringLocked');

  @override
  Future<void> write(String key, String value) async => throw StateError('KeyringLocked');
}

class _Silent implements KeyValueStore {
  @override
  Future<String?> read(String key) => Completer<String?>().future;

  @override
  Future<void> write(String key, String value) => Completer<void>().future;
}

void main() {
  late Directory dir;
  late FileKeyValueStore file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pindrel-store-');
    file = FileKeyValueStore(() async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('FileKeyValueStore', () {
    test('guarda e lê, e sobrevive a um objeto novo sobre o mesmo arquivo', () async {
      expect(await file.read('a'), isNull);
      await file.write('a', '1');
      await file.write('b', '2');
      await file.write('a', '3');
      expect(await file.read('a'), '3');
      expect(await FileKeyValueStore(() async => dir).read('b'), '2');
    });

    test('só o dono lê o arquivo (Linux e macOS)', () async {
      await file.write('a', '1');
      if (Platform.isWindows) return;
      final mode = File('${dir.path}/pindrel-store.json').statSync().mode & 0x1ff;
      expect(mode.toRadixString(8), '600');
    });

    test('escritas ao mesmo tempo não se perdem nem se misturam', () async {
      await Future.wait([for (var i = 0; i < 40; i++) file.write('k$i', 'v$i')]);
      for (var i = 0; i < 40; i++) {
        expect(await file.read('k$i'), 'v$i');
      }
      expect(dir.listSync().whereType<File>().map((f) => f.path.split('/').last), ['pindrel-store.json'], reason: 'no temporary file is left');
    });

    test('arquivo danificado vira vazio e a próxima escrita o conserta', () async {
      for (final junk in ['', 'não é json', '[]', '"x"', '{"a":1}', 'null', '{"a":']) {
        File('${dir.path}/pindrel-store.json').writeAsStringSync(junk);
        expect(await file.read('a'), isNull, reason: junk);
      }
      await file.write('a', 'ok');
      expect(await file.read('a'), 'ok');
    });

    test('a pasta ainda não existe: é criada', () async {
      final nested = FileKeyValueStore(() async => Directory('${dir.path}/a/b/c'));
      await nested.write('x', 'y');
      expect(await nested.read('x'), 'y');
    });

    test('uma escrita que falha não impede as seguintes', () async {
      var fail = true;
      final flaky = FileKeyValueStore(() async {
        if (fail) throw const FileSystemException('sem espaço');
        return dir;
      });
      await expectLater(flaky.write('a', '1'), throwsA(isA<FileSystemException>()));
      fail = false;
      await flaky.write('a', '2');
      expect(await flaky.read('a'), '2');
    });

    test('valores enormes e caracteres estranhos voltam iguais', () async {
      final big = 'ã€😀\n"\\' * 50000;
      await file.write('big', big);
      expect(await file.read('big'), big);
    });
  });

  group('DurableKeyValueStore', () {
    test('com o cofre funcionando, usa o cofre e não toca no arquivo', () async {
      final primary = MemoryKeyValueStore();
      final store = DurableKeyValueStore(primary, file);
      await store.write('a', '1');
      expect(primary.data['a'], '1');
      expect(await file.read('a'), isNull);
      expect(await store.read('a'), '1');
    });

    test('cofre trancado (erro): grava e lê pelo arquivo, sem exceção', () async {
      final store = DurableKeyValueStore(_Broken(), file);
      await store.write('a', '1');
      expect(await store.read('a'), '1');
      expect(await file.read('a'), '1');
    });

    test('cofre mudo: espera o limite e usa o arquivo', () async {
      final store = DurableKeyValueStore(_Silent(), file, primaryTimeout: const Duration(milliseconds: 100));
      final sw = Stopwatch()..start();
      await store.write('a', '1');
      expect(await store.read('a'), '1');
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('o cofre destrancou depois: o valor do cofre vale, e o do arquivo ainda é achado quando o cofre não tem', () async {
      await file.write('antigo', 'do-arquivo');
      final primary = MemoryKeyValueStore()..data['novo'] = 'do-cofre';
      final store = DurableKeyValueStore(primary, file);
      expect(await store.read('novo'), 'do-cofre');
      expect(await store.read('antigo'), 'do-arquivo');
      await file.write('x', 'velho');
      primary.data['x'] = 'novo';
      expect(await store.read('x'), 'novo', reason: 'the keyring wins over a stale file');
    });

    test('nem o cofre nem o arquivo funcionam: nada é lembrado, mas nada quebra', () async {
      final store = DurableKeyValueStore(_Broken(), FileKeyValueStore(() async => throw const FileSystemException('sem permissão')));
      await store.write('a', '1');
      expect(await store.read('a'), isNull);
    });
  });
}
