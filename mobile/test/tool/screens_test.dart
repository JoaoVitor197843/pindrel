// Draws the dashboard and the editor to PNG files so they can be set beside the web. Not part of the suite: run it with
//   SCREENS=/tmp/shots fvm flutter test test/tool/screens_test.dart
// It loads system fonts under the family names the app asks for, because the test engine has none.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/note_page.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/dashboard_page.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final file = File(f);
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

Workspace _seed(NotesDb db) {
  var t = DateTime(2026, 11, 7, 12).millisecondsSinceEpoch;
  final ws = Workspace(db, clock: () => t);
  for (final tag in [('pessoal', TagColor.accent), ('trabalho', TagColor.rust), ('servidor', TagColor.blue), ('ideias', TagColor.gold), ('leitura', TagColor.plum), ('receitas', TagColor.teal)]) {
    ws.addTag(tag.$1, tag.$2);
  }
  NotePage add(String title, String text, List<String> tags, int ageHours, {String icon = '', bool pin = false, String cover = ''}) {
    final p = ws.newPage(title);
    p.content = [Block('a${p.id}', BlockType.paragraph, text: text)];
    p.tags = tags;
    p.icon = icon;
    p.pinned = pin;
    p.cover = cover;
    ws.touch(p.id);
    p.updated = t - ageHours * 3600000;
    db.savePage(p);
    return p;
  }

  add('Reforma do apartamento — orçamento', 'Pedreiro confirmou para segunda. Falta decidir o piso da sala: vinílico ou taco recuperado. Orçamento total até agora R\$ 18.400.', ['pessoal'], 0);
  add('Migração do servidor para NixOS', 'Passos: exportar volumes do Docker, escrever configuration.nix, testar em VM antes de tocar no bare metal. Backup do Postgres primeiro.', ['servidor', 'trabalho'], 26, pin: true);
  add('Ideias para o Pindrel', 'Backlinks entre páginas. Modo leitura sem sidebar. Exportar tudo como markdown num zip. Atalho para busca global em qualquer tela.', ['ideias', 'trabalho'], 120, pin: true);
  add('Notas da reunião de produto', 'Roadmap do trimestre ficou em três frentes. A equipe de suporte pediu prioridade para o histórico de edições — parece justo.', ['trabalho'], 30);
  add('Pão de fermentação natural', 'Levain 20%, hidratação 72%, sal 2%. Autólise de 40 minutos e três dobras a cada 30. Forno a 250 °C com vapor nos primeiros 20.', ['receitas'], 72);
  final r = ws.newPage('Rotina de encerramento do trimestre');
  r.icon = '📋';
  r.cover = 'musgo';
  r.tags = ['trabalho'];
  r.content = [
    Block('r1', BlockType.heading, text: 'O que precisa acontecer antes do dia 31'),
    Block('r2', BlockType.paragraph, text: 'O fechamento tem três frentes que costumam colidir na última semana: conciliação financeira, revisão dos contratos que renovam em abril e o export dos relatórios para o conselho.'),
    Block('r3', BlockType.checklist, items: [ChecklistItem(id: 'i1', text: 'Fechar conciliação dos lançamentos de março', done: true), ChecklistItem(id: 'i2', text: 'Revisar as 4 renovações de contrato com o jurídico', done: true), ChecklistItem(id: 'i3', text: 'Rodar o export do relatório do conselho'), ChecklistItem(id: 'i4', text: 'Arquivar as páginas do trimestre anterior')]),
    Block('r4', BlockType.code, lang: 'python', text: '# rotina noturna: sela o que já está conciliado\ndef selar_trimestre(paginas, chave):\n    seladas = []\n    for pagina in paginas:\n        if pagina.status == "conciliada":\n            seladas.append(pagina.id)\n    return {"ok": True, "total": len(seladas)}'),
    Block('r5', BlockType.spoiler, text: 'segredo'),
    Block('r6', BlockType.secure, text: 'x'),
    Block('r7', BlockType.table, cols: [TableColumn(id: 'c1', label: 'Frente', w: 250), TableColumn(id: 'c2', label: 'Responsável', w: 170)], rows: [
      {'c1': 'Conciliação', 'c2': 'Marina'},
      {'c1': 'Contratos', 'c2': 'Jurídico'}
    ]),
  ];
  ws.touch(r.id);
  t += 1;
  return ws;
}

void main() {
  final out = Platform.environment['SCREENS'];
  if (out == null) return;
  Directory(out).createSync(recursive: true);

  Future<void> shot(WidgetTester tester, String name, Size size, Widget Function() home) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.dark, home: home())));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('screens', (tester) async {
    await _font('serif', ['/usr/share/fonts/liberation/LiberationSerif-Bold.ttf', '/usr/share/fonts/liberation/LiberationSerif-Regular.ttf']);
    await _font('monospace', ['/usr/share/fonts/TTF/DejaVuSansMono.ttf']);
    await _font('Roboto', ['/usr/share/fonts/TTF/DejaVuSans.ttf', '/usr/share/fonts/liberation/LiberationSans-Regular.ttf']);
    final db = NotesDb.inMemory();
    final ws = _seed(db);
    final editing = ws.pages.firstWhere((p) => p.title.startsWith('Rotina')).id;
    await shot(tester, 'dash-m', const Size(420, 900), () => DashboardPage(ws: ws));
    await shot(tester, 'dash-d', const Size(1300, 900), () => DashboardPage(ws: ws));
    await shot(tester, 'ed-m', const Size(420, 1500), () => EditorPage(ws: ws, pageId: editing));
    await shot(tester, 'ed-xl', const Size(1920, 1000), () => EditorPage(ws: ws, pageId: editing));
    await shot(tester, 'dash-xl', const Size(1920, 1000), () => DashboardPage(ws: ws));
    await shot(tester, 'ed-d', const Size(1300, 1100), () => EditorPage(ws: ws, pageId: editing));
  });
}
