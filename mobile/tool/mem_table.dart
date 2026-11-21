// Memory probe for tables, PSS read from /proc (Linux).
//   fvm flutter build linux --release -t tool/mem_table.dart
//   OUT=/tmp/t.jsonl MODE=today|pkg|rows SIZE=none|std|max build/linux/x64/release/bundle/Pindrel
// today: the app's page editor with its table (what ships). pkg: appflowy_editor's table as shipped by the package.
// rows: the package's table laid out by rows, only the near rows built (what `today` uses). model: only the document, no widgets.
// std = 4 tables of 8 columns x 40 rows (1280 cells); max = 1 table of 12 x 100 (1200 cells).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mobile/core/performance/frame_pacer.dart';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'dart:developer' as dev;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/appflowy/inline_marks.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

Map<String, int> read() {
  final r = <String, int>{};
  for (final l in File('/proc/self/smaps_rollup').readAsLinesSync()) {
    final m = RegExp(r'^(Pss|Pss_Anon|Rss):\s+(\d+)').firstMatch(l);
    if (m != null) r[m.group(1)!] = int.parse(m.group(2)!);
  }
  return r;
}

final sizes = switch (Platform.environment['SIZE']) {
  'max' => (tables: 1, cols: 12, rows: 100),
  'none' || 'text' => (tables: 0, cols: 8, rows: 40),
  _ => (tables: 4, cols: 8, rows: 40),
};

String cellText(int t, int r, int c) => r % 3 == 0 ? 'Valor **$r** na coluna $c' : 'Texto da célula $t.$r.$c com *ênfase*';

ScrollPosition? biggestScroll() {
  ScrollPosition? best;
  void visit(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final s = e.state as ScrollableState;
      if (s.widget.axisDirection == AxisDirection.down) {
        final p = s.position;
        if (p.hasContentDimensions && (best == null || p.maxScrollExtent > best!.maxScrollExtent)) best = p;
      }
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return best;
}

Document packageDoc() {
  final nodes = <Node>[];
  for (var t = 0; t < sizes.tables; t++) {
    nodes.add(paragraphNode(text: 'Tabela $t'));
    // fromList takes columns of rows
    final cols = [for (var c = 0; c < sizes.cols; c++) [for (var r = 0; r < sizes.rows; r++) cellText(t, r, c)]];
    final node = TableNode.fromList<String>(cols).node;
    // the cells hold the markers as typed; turn them into marks like the app does
    for (final cell in node.children) {
      final p = cell.children.first;
      final text = (p.delta?.toPlainText() ?? '');
      p.updateAttributes({'delta': marksToDelta(text).toJson()});
    }
    nodes.add(node);
  }
  if (nodes.isEmpty) nodes.add(paragraphNode(text: "vazio"));
  return Document.blank()..insert([0], nodes);
}

class Pkg extends StatelessWidget {
  const Pkg({super.key, required this.es, this.rows = false});
  final EditorState es;
  final bool rows;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AppFlowyEditor(
        editorState: es,
        editorStyle: EditorStyle.mobile(textStyleConfiguration: const TextStyleConfiguration(text: TextStyle(fontSize: 16, color: Colors.white))),
        blockComponentBuilders: {
          ...standardBlockComponentBuilderMap,
          if (rows) TableBlockKeys.type: TableBlockComponentBuilder(byRows: true, headerRow: false),
        },
      ),
    ),
  );
}

List<Block> todayBlocks() => Platform.environment['SIZE'] == 'text'
    ? [for (var i = 0; i < 300; i++) Block('p$i', i % 10 == 0 ? BlockType.heading : BlockType.paragraph, text: 'Parágrafo $i com **negrito**, *itálico* e `código` e mais texto para chegar perto de cento e sessenta caracteres no total, quebrando em duas linhas.')]
    : [
  for (var t = 0; t < sizes.tables; t++)
    Block('t$t', BlockType.table)
      ..cols = [for (var c = 0; c < sizes.cols; c++) TableColumn(id: 'c$c', label: 'Col $c')]
      ..rows = [for (var r = 0; r < sizes.rows; r++) {for (var c = 0; c < sizes.cols; c++) 'c$c': cellText(t, r, c)}],
];

Future<void> main() async {
  // PACE=30 probes the frame limiter (what "Economia de energia" turns on); PACE=auto lets the monitor decide
  PindrelBinding.ensureInitialized();
  final pace = Platform.environment['PACE'];
  if (pace == '30') FramePacer.slow = true; // not `mode`: the Workspace below sets that one from its settings
  if (pace == 'auto') FramePacer.watch();
  final mode = Platform.environment['MODE'] ?? 'today';
  late final EditorState es;
  switch (mode) {
    case 'model':
      es = EditorState(document: packageDoc());
      runApp(const MaterialApp(home: Scaffold(body: Text('model only'))));
    case 'pkg' || 'rows':
      es = EditorState(document: packageDoc());
      runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.dark, home: Pkg(es: es, rows: mode == 'rows')));
    default:
      final ws = Workspace(NotesDb.inMemory());
      final pid = ws.newPage('Página de teste').id;
      ws.contentOf(pid)!.addAll(todayBlocks());
      if (pace == 'eco') {
        // what Configurações > Economia de energia does
        ws.saveSettings(ws.settings.copy(power: PowerMode.saving));
        RowBudget.saving = true;
      }
      runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
  }
  final res = <String, Object>{'mode': mode, 'size': Platform.environment['SIZE'] ?? 'std'};
  // frame costs (build + raster, ms) while the page is scrolled end to end
  final frames = <double>[];
  var recording = false;
  SchedulerBinding.instance.addTimingsCallback((List<ui.FrameTiming> ts) {
    if (!recording) return;
    for (final t in ts) {
      frames.add(t.buildDuration.inMicroseconds / 1000 + t.rasterDuration.inMicroseconds / 1000);
    }
  });
  if (Platform.environment['DRIVE'] == 'external') {
    // Real input: something else (xdotool, a person) scrolls and clicks; this only listens to the frames and the memory.
    // The costs are build + raster of every frame, and the time between frames starts, over the seconds given.
    // frames while the wheel was turning (within 120 ms of an event) and the others (the page settling)
    var lastWheel = -1000000;
    if (Platform.environment['TICKER'] == '1') {
      // No input device: a ticker moves the page (about 900 px/s, end to end and back) at whatever rate the screen gives
      Timer(const Duration(seconds: 4), () {
        final p = biggestScroll();
        if (p == null) return;
        final span = p.maxScrollExtent;
        Ticker((el) {
          final x = (el.inMilliseconds * 0.9) % (2 * span);
          p.jumpTo(x < span ? x : 2 * span - x);
          lastWheel = dev.Timeline.now;
        }).start();
      });
    }
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerScrollEvent) lastWheel = dev.Timeline.now;
    });
    final movingWorst = <double>[];
    final movingBuild = <double>[], movingRaster = <double>[], movingCost = <double>[], idleCost = <double>[];
    final all = <double>[];
    final builds = <double>[];
    final rasters = <double>[];
    final gaps = <double>[];
    var last = Duration.zero;
    var on = false;
    SchedulerBinding.instance.addTimingsCallback((List<ui.FrameTiming> ts) {
      if (!on) return;
      for (final t in ts) {
        all.add(t.buildDuration.inMicroseconds / 1000 + t.rasterDuration.inMicroseconds / 1000);
        builds.add(t.buildDuration.inMicroseconds / 1000);
        rasters.add(t.rasterDuration.inMicroseconds / 1000);
        final at = Duration(microseconds: t.timestampInMicroseconds(ui.FramePhase.vsyncStart));
        if (at.inMicroseconds - lastWheel < 120000) {
          movingBuild.add(t.buildDuration.inMicroseconds / 1000);
          movingRaster.add(t.rasterDuration.inMicroseconds / 1000);
          movingWorst.add(t.buildDuration.inMicroseconds > t.rasterDuration.inMicroseconds ? t.buildDuration.inMicroseconds / 1000 : t.rasterDuration.inMicroseconds / 1000);
          movingCost.add(t.buildDuration.inMicroseconds / 1000 + t.rasterDuration.inMicroseconds / 1000);
        } else {
          idleCost.add(t.buildDuration.inMicroseconds / 1000 + t.rasterDuration.inMicroseconds / 1000);
        }
        if (last != Duration.zero) gaps.add((at - last).inMicroseconds / 1000);
        last = at;
      }
    });
    // CPU the process used (user + system, ms) between the two marks: what the battery pays for
    int cpuMs() {
      final f = File('/proc/self/stat').readAsStringSync().split(') ').last.split(' ');
      return (int.parse(f[11]) + int.parse(f[12])) * 10; // utime, stime in 1/100 s
    }

    var cpu0 = 0;
    Timer(const Duration(seconds: 4), () {
      res['settled'] = read();
      cpu0 = cpuMs();
      on = true;
    });
    Timer(Duration(seconds: int.tryParse(Platform.environment['PROBE_SECONDS'] ?? '') ?? 30), () {
      on = false;
      res['cpuMs'] = cpuMs() - cpu0;
      res['hz'] = WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate;
      res['fps'] = all.length / ((int.tryParse(Platform.environment['PROBE_SECONDS'] ?? '') ?? 30) - 4);
      res['after'] = read();
      Map<String, num> stats(List<double> v) {
        final x = [...v]..sort();
        if (x.isEmpty) return {};
        double q(double p) => x[((x.length - 1) * p).floor()];
        return {'n': x.length, 'mean': x.reduce((a, b) => a + b) / x.length, 'p50': q(.5), 'p90': q(.9), 'p95': q(.95), 'p99': q(.99), 'max': x.last, 'over8': all.where((e) => e > 8.33).length, 'over16': all.where((e) => e > 16.67).length};
      }

      res['cost'] = stats(all);
      res['build'] = stats(builds);
      res['mBuild'] = stats(movingBuild);
      res['mRaster'] = stats(movingRaster);
      res['mCost'] = stats(movingCost);
      res['mWorst'] = {...stats(movingWorst), 'ok120': movingWorst.where((e) => e <= 8.33).length, 'ok60': movingWorst.where((e) => e <= 16.67).length};
      res['idleCost'] = stats(idleCost);
      res['raster'] = stats(rasters);
      res['gap'] = stats(gaps);
      File(Platform.environment['OUT'] ?? '/dev/stdout').writeAsStringSync('${jsonEncode(res)}\n', mode: FileMode.append);
      exit(0);
    });
    return;
  }
  Timer(const Duration(seconds: 5), () async {
    res['settled'] = read();
    final p = biggestScroll();
    if (p != null) {
      recording = true;
      for (var i = 0; i < 60; i++) {
        p.jumpTo(p.maxScrollExtent * i / 59);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      res['scrolled'] = read();
      recording = false;
      frames.sort();
      if (frames.isNotEmpty) {
        res['frames'] = {'n': frames.length, 'p50': frames[frames.length ~/ 2], 'p95': frames[(frames.length * 0.95).floor()], 'max': frames.last};
      }
      p.jumpTo(0);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    // a calmer scroll, 30 px a frame (a finger fling), from a third of the way down
    if (p != null) {
      p.jumpTo(p.maxScrollExtent / 3);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      frames.clear();
      recording = true;
      for (var i = 0; i < 120; i++) {
        p.jumpTo(p.pixels + 30);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      recording = false;
      frames.sort();
      if (frames.isNotEmpty) {
        res['smooth'] = {'n': frames.length, 'p50': frames[frames.length ~/ 2], 'p95': frames[(frames.length * 0.95).floor()], 'max': frames.last};
      }
      p.jumpTo(0);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // touch one cell
    if (mode == 'pkg' || mode == 'rows') {
      es.selection = Selection.collapsed(Position(path: [1, 5, 0], offset: 3));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    res['editing'] = read();
    File(Platform.environment['OUT'] ?? '/dev/stdout').writeAsStringSync('${jsonEncode(res)}\n', mode: FileMode.append);
    exit(0);
  });
}
