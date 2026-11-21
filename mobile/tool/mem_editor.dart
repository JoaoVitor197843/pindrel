// Memory probe: opens the page editor on a page of 500 blocks and reports the process's own memory (Linux only).
//   fvm flutter build linux --release -t tool/mem_editor.dart
//   OUT=/tmp/mem.jsonl MODE=name build/linux/x64/release/bundle/mobile
// It prints the proportional set size (PSS) once the page has settled, after scrolling through the whole page, and
// after a burst of edits. Run it on both sides of a change to see what the change costs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

Map<String, int> read() {
  final r = <String, int>{};
  for (final l in File('/proc/self/smaps_rollup').readAsLinesSync()) {
    final m = RegExp(r'^(Pss|Pss_Anon):\s+(\d+)').firstMatch(l);
    if (m != null) r[m.group(1)!] = int.parse(m.group(2)!);
  }
  for (final l in File('/proc/self/status').readAsLinesSync()) {
    final m = RegExp(r'^(VmHWM):\s+(\d+)').firstMatch(l);
    if (m != null) r[m.group(1)!] = int.parse(m.group(2)!);
  }
  return r;
}

List<Block> page500() {
  final out = <Block>[];
  for (var i = 0; out.length < maxBlocks; i++) {
    switch (i % 10) {
      case 0:
        out.add(Block('h$i', BlockType.heading, text: 'Seção $i', level: 2));
      case 1 || 2 || 3 || 4:
        out.add(Block('p$i', BlockType.paragraph, text: 'Parágrafo $i com **negrito**, *itálico* e `código` e mais texto para chegar perto de cento e sessenta caracteres no total.'));
      case 5:
        out.add(Block('b$i', BlockType.bullet, text: 'item $i', indent: i % 3 == 0 ? 1 : 0));
      case 6:
        out.add(Block('c$i', BlockType.checklist, items: [ChecklistItem(id: 'i$i', text: 'tarefa $i')]));
      case 7:
        out.add(Block('q$i', BlockType.quote, text: 'citação $i'));
      case 8:
        out.add(Block('k$i', BlockType.code, lang: 'go', text: 'fmt.Println($i)'));
      default:
        out.add(Block('d$i', BlockType.divider));
    }
  }
  return out;
}

ScrollPosition? biggestScroll() {
  ScrollPosition? best;
  void visit(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final p = (e.state as ScrollableState).position;
      if (p.hasContentDimensions && (best == null || p.maxScrollExtent > best!.maxScrollExtent)) best = p;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return best;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = NotesDb.inMemory();
  final ws = Workspace(db);
  final pid = ws.newPage('Página de teste').id;
  ws.contentOf(pid)!.addAll(page500());
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
  final res = <String, Object>{'mode': Platform.environment['MODE'] ?? '?'};
  Timer(const Duration(seconds: 5), () async {
    res['settled'] = read();
    final p = biggestScroll();
    if (p != null) {
      for (var i = 0; i < 80; i++) {
        p.jumpTo(p.maxScrollExtent * i / 79);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      res['scrolled'] = read();
      p.jumpTo(0);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    File(Platform.environment['OUT'] ?? '/dev/stdout').writeAsStringSync('${jsonEncode(res)}\n', mode: FileMode.append);
    exit(0);
  });
}
