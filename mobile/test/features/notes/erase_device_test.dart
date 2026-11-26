import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/data/server_trust.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';
import 'package:mobile/features/notes/data/device_data.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/dashboard_page.dart';
import 'package:mobile/features/notes/presentation/pages/notes_gate.dart';
import 'package:mobile/features/notes/presentation/providers/notes_provider.dart';
import 'package:mobile/features/notes/presentation/widgets/settings_dialog.dart';
import 'package:mobile/features/notes/presentation/widgets/ui.dart';
import 'package:path/path.dart' as p;

void main() {
  late NotesDb db;
  late Workspace ws;
  late Directory dir;
  setUp(() {
    db = NotesDb.inMemory();
    ws = Workspace(db);
    dir = Directory.systemTemp.createTempSync('pindrel_erase_ui');
  });
  tearDown(() {
    ws.dispose();
    db.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> openSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(Toast.clear);
    await tester.tap(find.byTooltip('Menu da conta de Você'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dados do aparelho'));
    await tester.pumpAndSettle();
  }

  // the progress screen spins until the work ends, so pumpAndSettle cannot wait for it: real time for the file work, fake
  // time for the short wait before the databases are deleted
  Future<void> work(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Widget app(Widget home, {List<Override> overrides = const []}) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.dark, home: home),
  );

  testWidgets('sem o gancho a seção não aparece', (tester) async {
    await tester.pumpWidget(app(Scaffold(body: Builder(builder: (c) => TextButton(
      onPressed: () => showDialog<void>(
        context: c,
        builder: (_) => SettingsDialog(ws: ws, userName: 'Você', server: 'x', onAccount: () {}, onToast: (_) {}),
      ),
      child: const Text('abrir'),
    )))));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Dados do aparelho'), findsNothing);
  });

  testWidgets('cancelar a confirmação não apaga nada; confirmar apaga os arquivos, a sessão e volta ao login', (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    var cleared = 0;
    final files = [for (final n in ['notes.db', 'notes.db-wal', 'pindrel-store.json']) File(p.join(dir.path, n))..writeAsStringSync('x')];
    final device = DeviceData(directory: () async => dir, clearSecure: () async => cleared++);
    await tester.pumpWidget(app(
      DashboardPage(ws: ws),
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        deviceDataProvider.overrideWithValue(device),
        // the real one would open a file in the machine's own support folder
        workspaceProvider.overrideWith((ref) => Workspace(NotesDb.inMemory())),
      ],
    ));
    await tester.pumpAndSettle();
    await openSection(tester);

    // a wrong tap and a change of mind: nothing happens
    await tester.tap(find.byKey(const Key('erase-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase-cancel')));
    await tester.pumpAndSettle();
    expect(files.every((f) => f.existsSync()), isTrue);
    expect(cleared, 0);

    // sure now; a second tap on the same button while it works must not run it twice
    await tester.tap(find.byKey(const Key('erase-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase-confirm')));
    await work(tester);
    expect(files.any((f) => f.existsSync()), isFalse);
    expect(cleared, 1);
    expect(find.text('Continuar offline neste dispositivo'), findsOneWidget, reason: 'back at the login');
  });

  testWidgets('a partir das notas do aparelho, o banco é fechado antes de os arquivos serem apagados', (tester) async {
    // NotesGate watches the device's workspace: invalidating it there reopened notes.db at once, and on Windows an open
    // file cannot be deleted, so the notes stayed behind under "Não foi possível apagar tudo"
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dbs = <NotesDb>[];
    bool? openWhileErasing;
    final device = DeviceData(directory: () async => dir, clearSecure: () async => openWhileErasing = dbs.any((d) => d.isOpen));
    await tester.pumpWidget(app(
      const NotesGate(),
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        deviceDataProvider.overrideWithValue(device),
        workspaceProvider.overrideWith((ref) {
          final db = NotesDb.inMemory();
          dbs.add(db);
          return trackedWorkspace(ref, Workspace(db));
        }),
      ],
    ));
    await tester.pumpAndSettle();
    await openSection(tester);
    await tester.tap(find.byKey(const Key('erase-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase-confirm')));
    await work(tester);
    expect(openWhileErasing, isFalse, reason: 'a notes database was open while its files were deleted');
    expect(find.text('Continuar offline neste dispositivo'), findsOneWidget);
  });

  testWidgets('quando um arquivo não pode ser apagado o erro aparece e dá para voltar', (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final device = DeviceData(directory: () async => throw const FileSystemException('sem permissão'), clearSecure: () async {});
    await tester.pumpWidget(app(
      DashboardPage(ws: ws),
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        deviceDataProvider.overrideWithValue(device),
        workspaceProvider.overrideWith((ref) => Workspace(NotesDb.inMemory())),
      ],
    ));
    await tester.pumpAndSettle();
    await openSection(tester);
    await tester.tap(find.byKey(const Key('erase-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase-confirm')));
    await work(tester);
    expect(find.text('Não foi possível apagar tudo'), findsOneWidget);
    await tester.tap(find.text('Voltar ao início'));
    await tester.pumpAndSettle();
    expect(find.text('Continuar offline neste dispositivo'), findsOneWidget);
  });
}
