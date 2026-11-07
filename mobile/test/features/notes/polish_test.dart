import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/dock.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/dashboard_page.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';
import 'package:mobile/features/notes/presentation/widgets/motion.dart';
import 'package:mobile/features/notes/presentation/widgets/ui.dart';

late NotesDb db;
late Workspace ws;
late String pid;
var clock = DateTime(2026, 11, 7, 12).millisecondsSinceEpoch;

Future<void> pump(WidgetTester tester, Widget home, {Size size = const Size(1300, 900), bool disableAnimations = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(Toast.clear);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: disableAnimations), child: child!),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    db = NotesDb.inMemory();
    ws = Workspace(db, clock: () => clock += 10);
    pid = ws.newPage('Minha página').id;
    KeyboardMode.reset(false);
  });
  tearDown(() {
    ws.dispose();
    db.dispose();
  });

  group('tamanho dos painéis encostados (dockScale)', () {
    test('1 até a largura mínima, cresce com a janela e para em 1,7', () {
      expect(dockScale(0), 1);
      expect(dockScale(1339), 1);
      expect(dockScale(1340), 1);
      expect(dockScale(1920), closeTo(1.6, 0.01));
      expect(dockScale(2600), 1.7);
      expect(dockScale(100000), 1.7);
    });
    test('valores absurdos não quebram', () {
      expect(dockScale(double.nan), 1);
      expect(dockScale(double.infinity), 1);
      expect(dockScale(-5), 1);
    });
    test('só cresce, nunca encolhe', () {
      var last = 1.0;
      for (var w = 1300.0; w < 3000; w += 50) {
        expect(dockScale(w), greaterThanOrEqualTo(last));
        last = dockScale(w);
      }
    });
    testWidgets('numa janela grande o painel fica maior que em uma média', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(1400, 1000));
      double heightOf(Finder f) => tester.getBottomRight(f).dy - tester.getTopLeft(f).dy;
      final small = heightOf(find.text('Propriedades'));
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(2200, 1200));
      final big = heightOf(find.text('Propriedades'));
      expect(big, greaterThan(small * 1.3));
    });
  });

  group('modo zen', () {
    setUp(() => ws.page(pid)!.content = [Block('a', BlockType.paragraph, text: 'uma duas três'), Block('b', BlockType.paragraph, text: 'quatro')]);

    testWidgets('mostra a contagem de palavras no singular e no plural', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      expect(find.text('4 palavras'), findsOneWidget);
      expect(find.text('Sair do zen'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
      ws.page(pid)!.content = [Block('a', BlockType.paragraph, text: 'só')];
      await tester.enterText(find.byType(TextField).at(1), 'um');
      await tester.pumpAndSettle();
      expect(find.text('1 palavra'), findsOneWidget);
    });
    testWidgets('a contagem acompanha o que se escreve', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'quatro'), 'quatro cinco seis');
      await tester.pumpAndSettle();
      expect(find.text('6 palavras'), findsOneWidget);
    });
    testWidgets('a página vazia conta zero palavras', (tester) async {
      ws.page(pid)!.content = [];
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      expect(find.text('0 palavras'), findsOneWidget);
    });
    testWidgets('o botão e a tecla Esc saem do zen', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair do zen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zen-words')), findsNothing);
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zen-words')), findsNothing);
    });
    testWidgets('quando um bloco está sendo escrito os outros esmaecem', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      double opacityOf(String text) {
        final row = find.ancestor(of: find.widgetWithText(TextField, text), matching: find.byType(AnimatedOpacity)).first;
        return tester.widget<AnimatedOpacity>(row).opacity;
      }

      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      expect(opacityOf('quatro'), 1);
      await tester.tap(find.widgetWithText(TextField, 'quatro'));
      await tester.pumpAndSettle();
      expect(opacityOf('quatro'), 1);
      expect(opacityOf('uma duas três'), closeTo(0.38, 0.001));
    });
    testWidgets('fora do zen nada esmaece', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.tap(find.widgetWithText(TextField, 'quatro'));
      await tester.pumpAndSettle();
      final op = find.ancestor(of: find.widgetWithText(TextField, 'uma duas três'), matching: find.byType(AnimatedOpacity)).first;
      expect(tester.widget<AnimatedOpacity>(op).opacity, 1);
    });
  });

  group('Ctrl+K', () {
    testWidgets('abre a busca rápida do painel em qualquer lugar da tela, e Ctrl não basta sem o K', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('esc'), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('esc'), findsOneWidget);
      expect(find.text('PÁGINAS'), findsOneWidget);
    });
    testWidgets('também funciona com o foco no campo de busca, e com Cmd+K', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('esc'), findsOneWidget);
    });
    testWidgets('com a busca aberta, Esc fecha e Ctrl+K de novo não abre outra por cima', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('esc'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('esc'), findsNothing);
    });
  });

  group('borda do foco (só pelo teclado)', () {
    testWidgets('aparece ao navegar com Tab e some ao clicar', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      expect(find.byKey(const Key('focus-ring')), findsNothing);
      // the first stops are fields without a ring of their own: walk on until a button has the focus
      for (var i = 0; i < 6 && find.byKey(const Key('focus-ring')).evaluate().isEmpty; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(find.byKey(const Key('focus-ring')), findsAtLeastNWidgets(1));
      await tester.tap(find.byTooltip('Grade'));
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')), findsNothing);
    });
    testWidgets('andar com Tab muda de lugar; um clique do mouse não deixa borda em nada', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      await tester.tap(find.byKey(const Key('new-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('focus-ring')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')), findsAtLeastNWidgets(1));
    });
    testWidgets('só Shift ou Ctrl apertados sozinhos não ligam a borda', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(KeyboardMode.active.value, false);
    });
    testWidgets('o botão do editor também mostra a borda', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')), findsAtLeastNWidgets(1));
    });
  });

  group('entradas animadas', () {
    testWidgets('sobe e aparece, e termina sem deixar nada agendado', (tester) async {
      await pump(tester, const Scaffold(body: Center(child: Entrance(delay: Duration(milliseconds: 100), child: Text('oi')))));
      expect(find.text('oi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('no começo está transparente e deslocado; no fim, inteiro', (tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: Entrance(child: Text('oi'))))));
      final opacity = tester.widget<Opacity>(find.ancestor(of: find.text('oi'), matching: find.byType(Opacity)).first).opacity;
      expect(opacity, lessThan(0.2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('oi'), matching: find.byType(Opacity)).first).opacity, 1);
    });
    testWidgets('com "reduzir movimento" o conteúdo já aparece pronto', (tester) async {
      await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(disableAnimations: true), child: const Scaffold(body: Entrance(child: Text('oi'))))));
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('oi'), matching: find.byType(Opacity)).first).opacity, 1);
    });
    testWidgets('desligada, não anima (uma linha que volta a ser desenhada)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Entrance(enabled: false, child: Text('oi')))));
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('oi'), matching: find.byType(Opacity)).first).opacity, 1);
    });
    testWidgets('cada tipo termina inteiro e visível', (tester) async {
      for (final kind in EntranceKind.values) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: Entrance(key: ValueKey(kind), kind: kind, child: const Text('oi'))))));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.widget<Opacity>(find.ancestor(of: find.text('oi'), matching: find.byType(Opacity)).first).opacity, 1, reason: kind.name);
        expect(tester.takeException(), isNull);
      }
    });
    testWidgets('as linhas do editor entram uma vez só, e não de novo ao voltar a ser desenhadas', (tester) async {
      ws.page(pid)!.content = [for (var i = 0; i < 80; i++) Block('p$i', BlockType.paragraph, text: 'linha $i')];
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(900, 700));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pump();
      // a row scrolled back into view is already whole, not fading in again
      final first = find.ancestor(of: find.widgetWithText(TextField, 'linha 0'), matching: find.byType(Opacity)).first;
      expect(tester.widget<Opacity>(first).opacity, 1);
    });
    testWidgets('o aviso de página aparece com um pulinho e some sozinho', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      await tester.tap(find.byKey(const Key('new-page')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Página criada'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('Página criada'), findsNothing);
    });
  });

  group('cartões e colunas', () {
    testWidgets('quatro colunas em janelas muito largas', (tester) async {
      for (var i = 0; i < 9; i++) {
        ws.newPage('Página $i');
      }
      await pump(tester, DashboardPage(ws: ws), size: const Size(2000, 1200));
      final cards = tester.widgetList(find.byKey(const Key('page-card'))).length;
      final y = tester.getTopLeft(find.byKey(const Key('page-card')).first).dy;
      final inFirstRow = tester.widgetList(find.byKey(const Key('page-card'))).where((w) => tester.getTopLeft(find.byWidget(w)).dy == y).length;
      expect(cards, greaterThan(4));
      expect(inFirstRow, 4);
    });
    testWidgets('o cartão ficou compacto: menos de 200 px de altura com texto de um parágrafo', (tester) async {
      final p = ws.page(pid)!;
      p.excerpt = 'Passos: exportar volumes do Docker, escrever configuration.nix, testar em VM antes de tocar no bare metal. Backup do Postgres primeiro.';
      p.tags = [ws.addTag('servidor')!.id, ws.addTag('trabalho')!.id];
      await pump(tester, DashboardPage(ws: ws), size: const Size(1500, 900));
      expect(tester.getSize(find.byKey(const Key('page-card'))).height, lessThan(200));
    });
  });

  group('borda do foco nos blocos', () {
    testWidgets('um clique num bloco de texto mostra a borda (campo de texto), sem precisar do teclado', (tester) async {
      ws.page(pid)!.content = [Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois')];
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      expect(find.byKey(const Key('focus-ring')), findsNothing);
      await tester.tap(find.widgetWithText(TextField, 'dois'));
      await tester.pump();
      expect(KeyboardMode.active.value, false);
      expect(find.byKey(const Key('focus-ring')), findsAtLeastNWidgets(1));
      final ring = tester.getRect(find.byKey(const Key('focus-ring')).first);
      final field = tester.getRect(find.widgetWithText(TextField, 'dois'));
      // 2 px of border drawn 2 px off the edge: the ring sits outside the field on every side
      expect(ring.left, lessThan(field.left));
      expect(ring.right, greaterThan(field.right));
      expect(ring.top, lessThan(field.top));
      expect(ring.bottom, greaterThan(field.bottom));
    });
    testWidgets('só o bloco com o foco tem a borda, e ela some quando o foco sai', (tester) async {
      ws.page(pid)!.content = [Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois')];
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.tap(find.widgetWithText(TextField, 'um'));
      await tester.pump();
      final before = find.byKey(const Key('focus-ring')).evaluate().length;
      await tester.tap(find.widgetWithText(TextField, 'dois'));
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')).evaluate().length, before);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')), findsNothing);
    });
    testWidgets('o título e os campos de uma tarefa também ganham a borda', (tester) async {
      ws.page(pid)!.content = [makeBlock(BlockType.checklist)];
      await pump(tester, EditorPage(ws: ws, pageId: pid));
      await tester.tap(find.widgetWithText(TextField, 'Tarefa'));
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')), findsAtLeastNWidgets(1));
      await tester.tap(find.widgetWithText(TextField, 'Minha página'));
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')), findsAtLeastNWidgets(1));
    });
    testWidgets('um botão clicado com o mouse continua sem borda', (tester) async {
      await pump(tester, DashboardPage(ws: ws));
      await tester.tap(find.byTooltip('Lista'));
      await tester.pump();
      expect(find.byKey(const Key('focus-ring')), findsNothing);
    });
  });

  group('setas dos painéis', () {
    testWidgets('encostados: setas redondas de 44 px na faixa de cada painel, no meio da área da página', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(1500, 900));
      final close = find.byTooltip('Fechar painel');
      expect(tester.getSize(close), const Size(44, 44));
      // beside the panel, near the screen's edge: the right strip is the last 48 px
      expect(tester.getCenter(close).dx, greaterThan(1500 - 48));
      final area = tester.getRect(find.byType(CustomScrollView).evaluate().isEmpty ? find.byType(ReorderableListView) : find.byType(CustomScrollView));
      expect(tester.getCenter(close).dy, closeTo(area.center.dy, 2));
    });
    testWidgets('as setas apontam para fora para fechar e para dentro para abrir', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(1500, 900));
      IconData iconOf(String tooltip) => tester.widget<Icon>(find.descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon))).icon!;
      expect(iconOf('Fechar painel'), Icons.chevron_right);
      expect(iconOf('Fechar propriedades'), Icons.chevron_left);
      await tester.tap(find.byTooltip('Fechar painel'));
      await tester.tap(find.byTooltip('Fechar propriedades'));
      await tester.pumpAndSettle();
      expect(iconOf('Abrir painel'), Icons.chevron_left);
      expect(iconOf('Abrir propriedades'), Icons.chevron_right);
    });
    testWidgets('janela estreita: abas de 32x64 coladas nas bordas, no meio da JANELA (cabeçalho incluso)', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(900, 800));
      final open = find.byTooltip('Abrir painel');
      expect(tester.getSize(open), const Size(32, 64));
      expect(tester.getTopRight(open).dx, 900);
      expect(tester.getCenter(open).dy, closeTo(400, 1));
      final left = find.byTooltip('Abrir propriedades');
      expect(tester.getTopLeft(left).dx, 0);
      expect(tester.getCenter(left).dy, closeTo(400, 1));
    });
    testWidgets('a gaveta abre com fundo escuro, a seta redonda ao lado dela, e fecha por qualquer um dos dois', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(900, 800));
      await tester.tap(find.byTooltip('Abrir painel'));
      await tester.pumpAndSettle();
      expect(find.text('Painel'), findsOneWidget);
      expect(find.byTooltip('Abrir painel'), findsNothing, reason: 'the edge tab goes away while a drawer is open');
      final close = find.byTooltip('Fechar painel');
      expect(tester.getSize(close), const Size(44, 44));
      // the arrow stands in a 56 px strip on the page side of the drawer (352 px wide: the drawer is cut at 80% of narrow windows)
      expect(tester.getCenter(close).dx, closeTo(900 - 352 - 28, 1));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Painel'), findsNothing);
      await tester.tap(find.byTooltip('Abrir propriedades'));
      await tester.pumpAndSettle();
      expect(find.text('Propriedades'), findsOneWidget);
      await tester.tapAt(const Offset(700, 400));
      await tester.pumpAndSettle();
      expect(find.text('Propriedades'), findsNothing);
    });
    testWidgets('em tela de celular a gaveta ocupa no máximo 80% da largura', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(400, 800));
      await tester.tap(find.byTooltip('Abrir propriedades'));
      await tester.pumpAndSettle();
      final title = tester.getTopLeft(find.text('Propriedades'));
      expect(title.dx, lessThan(400 * 0.8));
      final arrow = tester.getCenter(find.byTooltip('Fechar propriedades'));
      expect(arrow.dx, closeTo(400 * 0.8 + 28, 1));
    });
    testWidgets('abrir uma gaveta e escolher um título do painel leva até ele e fecha a gaveta', (tester) async {
      ws.page(pid)!.content = [Block('h', BlockType.heading, text: 'Capítulo um', level: 1), for (var i = 0; i < 20; i++) Block('p$i', BlockType.paragraph, text: 'linha $i')];
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(900, 800));
      await tester.tap(find.byTooltip('Abrir painel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capítulo um').last);
      await tester.pumpAndSettle();
      expect(find.text('Painel'), findsNothing);
    });
    testWidgets('no menu "⋯" do celular, Propriedades e Painel abrem as gavetas', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(400, 800));
      await tester.tap(find.byTooltip('Mais opções da página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Painel'));
      await tester.pumpAndSettle();
      expect(find.text('NESTA PÁGINA'), findsOneWidget);
    });
    testWidgets('em tela pequena demais para as abas, o menu "⋯" do cabeçalho abre as gavetas', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(340, 800));
      expect(find.byTooltip('Abrir painel'), findsNothing);
      await tester.tap(find.byTooltip('Mais opções da página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Painel'));
      await tester.pumpAndSettle();
      expect(find.text('NESTA PÁGINA'), findsOneWidget);
    });
  });

  group('botões de ação do painel', () {
    testWidgets('ocupam a largura do painel, como na web', (tester) async {
      await pump(tester, EditorPage(ws: ws, pageId: pid), size: const Size(1500, 900));
      final pin = find.ancestor(of: find.text('Fixar página'), matching: find.byType(Container)).first;
      final panelInner = 240.0 - 32;
      expect(tester.getRect(pin).width, closeTo(panelInner, 1));
    });
  });
}
