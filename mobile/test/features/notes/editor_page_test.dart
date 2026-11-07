import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/note_page.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';
import 'package:mobile/features/notes/presentation/widgets/ui.dart';

late NotesDb db;
late Workspace ws;
late String pid;
var clock = DateTime(2026, 11, 7, 12).millisecondsSinceEpoch;

Future<void> pumpEditor(WidgetTester tester, {Size size = const Size(900, 1100), double textScale = 1, String? id}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(Toast.clear);
  // the page is closed (and saved) before the database goes away
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: EditorPage(ws: ws, pageId: id ?? pid),
    ),
  );
  await tester.pumpAndSettle();
}

List<Block> body() => ws.page(pid)!.content ?? ws.contentOf(pid)!;
void setBody(List<Block> blocks) => ws.page(pid)!.content = blocks;

Finder get draft => find.byKey(const Key('draft'));
Finder get titleField => find.descendant(of: find.byKey(const ValueKey('title')), matching: find.byType(TextField));
Finder field(String text) => find.widgetWithText(TextField, text);

/// Clipboard calls have no platform behind them in tests: answer them, and keep what was copied.
String? mockClipboard(WidgetTester tester, void Function(String) onCopy) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') onCopy((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return null;
}

void main() {
  setUp(() {
    db = NotesDb.inMemory();
    ws = Workspace(db, clock: () => clock += 10);
    pid = ws.newPage('Minha página').id;
  });
  tearDown(() {
    ws.dispose();
    db.dispose();
  });

  group('cabeçalho e título', () {
    testWidgets('mostra o título, o caminho e o aviso de salvando', (tester) async {
      await pumpEditor(tester, size: const Size(1300, 1000));
      expect(find.text('Dashboard'), findsOneWidget);
      await tester.enterText(titleField, 'Outro nome');
      await tester.pump();
      expect(ws.page(pid)!.title, 'Outro nome');
      expect(find.text('salvando…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('salvo automaticamente'), findsOneWidget);
    });
    testWidgets('o botão Dashboard volta', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => EditorPage(ws: ws, pageId: pid))), child: const Text('abrir')))))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('←'));
      await tester.pumpAndSettle();
      expect(find.text('abrir'), findsOneWidget);
    });
    testWidgets('título enorme, vazio ou com quebras não quebra', (tester) async {
      await pumpEditor(tester);
      await tester.enterText(titleField, 'a\n\n b' * 300);
      await tester.pump();
      expect(ws.page(pid)!.title.length, lessThanOrEqualTo(maxTitle));
      await tester.enterText(titleField, '');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('blocos', () {
    testWidgets('a linha de baixo cria um parágrafo com o que se digita', (tester) async {
      await pumpEditor(tester);
      await tester.enterText(draft, 'olá mundo');
      await tester.pump();
      expect(body().single.text, 'olá mundo');
      expect(draft, findsOneWidget);
      expect((tester.widget<TextField>(draft).controller!).text, '');
    });
    testWidgets('"/" na linha de baixo abre a lista de blocos', (tester) async {
      await pumpEditor(tester);
      await tester.enterText(draft, '/');
      await tester.pumpAndSettle();
      expect(find.text('Título 1'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Divisor'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Divisor'));
      await tester.pumpAndSettle();
      expect(body().map((b) => b.type), [BlockType.divider]);
    });
    testWidgets('página vazia oferece os botões "Começar com"', (tester) async {
      await pumpEditor(tester);
      expect(find.text('Começar com'), findsOneWidget);
      await tester.tap(find.text('Checklist'));
      await tester.pumpAndSettle();
      expect(body().single.type, BlockType.checklist);
      expect(find.text('Começar com'), findsNothing);
    });
    testWidgets('"# ", "- ", "1. " e "> " viram título, lista, lista numerada e citação', (tester) async {
      for (final (typed, type) in [('# ', BlockType.heading), ('- ', BlockType.bullet), ('1. ', BlockType.numbered), ('> ', BlockType.quote)]) {
        ws.page(pid)!.content = [Block('a', BlockType.paragraph, text: '')];
        await pumpEditor(tester);
        await tester.enterText(find.widgetWithText(TextField, '').first, 'x');
        await tester.enterText(find.byType(TextField).at(1), typed);
        await tester.pump();
        expect(body().first.type, type, reason: typed);
        expect(body().first.text, '', reason: typed);
      }
    });
    testWidgets('"/" no parágrafo vazio troca pelo bloco escolhido', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: '')]);
      await pumpEditor(tester);
      await tester.enterText(find.byType(TextField).at(1), '/');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Citação'));
      await tester.pumpAndSettle();
      expect(body().map((b) => b.type), [BlockType.quote]);
    });
    testWidgets('Enter no meio parte o bloco; Enter num item vazio sai da lista', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'olá mundo')]);
      await pumpEditor(tester);
      await tester.enterText(field('olá mundo'), 'olá\n mundo');
      await tester.pump();
      expect(body().map((b) => b.text), ['olá', ' mundo']);
      setBody([Block('b', BlockType.bullet, text: '', indent: 0)]);
      await pumpEditor(tester, id: pid);
      await tester.enterText(find.byType(TextField).at(1), '\n');
      await tester.pump();
      expect(body().single.type, BlockType.paragraph);
    });
    testWidgets('lista de tarefas: marca, escreve, acrescenta e tira', (tester) async {
      setBody([makeBlock(BlockType.checklist)]);
      await pumpEditor(tester);
      await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.checked != null).first);
      await tester.pump();
      expect(body().first.items!.first.done, true);
      await tester.enterText(field('Tarefa'), 'pão');
      await tester.pump();
      expect(body().first.items!.first.text, 'pão');
      await tester.tap(find.text('+ Item'));
      await tester.pumpAndSettle();
      expect(body().first.items!.length, 2);
      await tester.enterText(find.widgetWithText(TextField, 'Tarefa').last, 'x\n');
      await tester.pump();
      expect(body().first.items!.length, 3);
      await tester.tap(find.byTooltip('Remover item').first);
      await tester.pumpAndSettle();
      expect(body().first.items!.length, 2);
    });
    testWidgets('tabela: escreve numa célula, acrescenta e remove linhas e colunas', (tester) async {
      setBody([makeBlock(BlockType.table)]);
      await pumpEditor(tester, size: const Size(1100, 1000));
      final b = body().first;
      await tester.enterText(find.byType(TextField).at(5), 'oi');
      await tester.pump();
      expect(b.rows!.any((r) => r.values.contains('oi')), true);
      await tester.tap(find.text('+ linha'));
      await tester.tap(find.text('+ coluna'));
      await tester.pumpAndSettle();
      expect((b.rows!.length, b.cols!.length), (4, 4));
      // the table scrolls sideways inside the page column: the first column is the one in view
      await tester.tap(find.byTooltip('Remover coluna Coluna 1'));
      await tester.pumpAndSettle();
      expect(body().first.cols!.length, 3);
    });
    testWidgets('link com endereço perigoso é recusado; um bom é guardado', (tester) async {
      setBody([makeBlock(BlockType.bookmark)]);
      await pumpEditor(tester);
      await tester.tap(find.text('Link sem endereço'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Endereço (https://…)'), 'javascript:alert(1)');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Endereço inválido'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Endereço (https://…)'), 'exemplo.com/a');
      await tester.enterText(find.widgetWithText(TextField, 'Título (opcional)'), 'Exemplo');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(body().first.url, 'https://exemplo.com/a');
      expect(find.text('Exemplo'), findsOneWidget);
    });
    testWidgets('vídeo só aceita http(s)', (tester) async {
      setBody([makeBlock(BlockType.video)]);
      await pumpEditor(tester);
      await tester.tap(find.textContaining('toque para definir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Endereço (https://…)'), 'a@b.com');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Use um endereço http ou https'), findsOneWidget);
    });
    testWidgets('spoiler fica escondido até tocar e esconde de novo', (tester) async {
      setBody([Block('s', BlockType.spoiler, text: 'segredo do final')]);
      await pumpEditor(tester);
      expect(find.text('segredo do final'), findsNothing);
      await tester.tap(find.text('Clique para revelar'));
      await tester.pumpAndSettle();
      expect(find.text('segredo do final'), findsOneWidget);
      await tester.tap(find.text('ocultar'));
      await tester.pumpAndSettle();
      expect(find.text('segredo do final'), findsNothing);
    });
    testWidgets('bloco seguro nunca mostra o texto e explica o cofre', (tester) async {
      setBody([Block('s', BlockType.secure, text: 'senha-1234')]);
      await pumpEditor(tester);
      expect(find.textContaining('senha-1234'), findsNothing);
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      expect(find.textContaining('O cofre ainda não está pronto'), findsOneWidget);
      expect(find.textContaining('senha-1234'), findsNothing);
    });
    testWidgets('código: linguagem e texto', (tester) async {
      setBody([makeBlock(BlockType.code)]);
      await pumpEditor(tester);
      await tester.enterText(field('Código'), 'def f():\n  return "x" # n');
      await tester.pump();
      expect(body().first.text, contains('def f()'));
      await tester.tap(find.text('TEXTO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PYTHON').last);
      await tester.pumpAndSettle();
      expect(body().first.lang, 'python');
      expect(tester.takeException(), isNull);
    });
    testWidgets('sumário lista os títulos e leva até eles', (tester) async {
      setBody([Block('h', BlockType.heading, text: 'Capítulo um', level: 1), for (var i = 0; i < 30; i++) Block('p$i', BlockType.paragraph, text: 'linha $i'), makeBlock(BlockType.toc)]);
      await pumpEditor(tester);
      await tester.scrollUntilVisible(find.text('SUMÁRIO'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Capítulo um').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('link para página: escolhe, abre a outra e não oferece a lixeira', (tester) async {
      final other = ws.newPage('Destino');
      final trashed = ws.newPage('Lixo');
      ws.trash(trashed.id);
      setBody([makeBlock(BlockType.pagelink)]);
      await pumpEditor(tester);
      await tester.tap(find.text('Escolha uma página'));
      await tester.pumpAndSettle();
      expect(find.text('Lixo'), findsNothing);
      await tester.tap(find.text('Destino'));
      await tester.pumpAndSettle();
      expect(body().first.pageId, other.id);
      await tester.tap(find.text('Abrir página'));
      await tester.pumpAndSettle();
      expect(find.text('Destino'), findsWidgets);
    });
    testWidgets('toggle e título com toggle abrem e fecham', (tester) async {
      setBody([Block('t', BlockType.toggle, text: 'Título', body: 'escondido')]);
      await pumpEditor(tester);
      expect(find.text('escondido'), findsNothing);
      await tester.tap(find.byTooltip('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('escondido'), findsOneWidget);
      await tester.enterText(field('escondido'), 'novo corpo');
      await tester.pump();
      expect(body().first.body, 'novo corpo');
    });
    testWidgets('limite de blocos avisa em vez de quebrar', (tester) async {
      setBody([for (var i = 0; i < maxBlocks; i++) Block('d$i', BlockType.divider)]);
      await pumpEditor(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400000));
      await tester.pumpAndSettle();
      await tester.enterText(draft, 'mais um');
      await tester.pump();
      expect(find.textContaining('limite de $maxBlocks blocos'), findsOneWidget);
      expect(body().length, maxBlocks);
    });
  });

  group('menu do bloco', () {
    testWidgets('subir, descer, duplicar e excluir', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois')]);
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Opções do bloco 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subir'));
      await tester.pumpAndSettle();
      expect(body().map((b) => b.text), ['dois', 'um']);
      await tester.tap(find.byTooltip('Opções do bloco 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicar'));
      await tester.pumpAndSettle();
      expect(body().map((b) => b.text), ['dois', 'dois', 'um']);
      await tester.tap(find.byTooltip('Opções do bloco 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(body().map((b) => b.text), ['dois', 'dois']);
    });
    testWidgets('Subir no primeiro e Descer no último ficam desligados', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois')]);
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Opções do bloco 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subir'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(body().map((b) => b.text), ['um', 'dois']);
    });
    testWidgets('transformar um texto em título e em lista', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'um')]);
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Opções do bloco 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Título 1').last);
      await tester.pumpAndSettle();
      expect((body().first.type, body().first.level, body().first.text), (BlockType.heading, 1, 'um'));
      await tester.tap(find.byTooltip('Opções do bloco 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lista numerada'));
      await tester.pumpAndSettle();
      expect(body().first.type, BlockType.numbered);
      await tester.tap(find.byTooltip('Opções do bloco 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aninhar'));
      await tester.pumpAndSettle();
      expect(body().first.indent, 1);
    });
    testWidgets('o tom de um destaque', (tester) async {
      setBody([Block('c', BlockType.callout, text: 'cuidado')]);
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Opções do bloco 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('⚠️'));
      await tester.pumpAndSettle();
      expect(body().first.tone, CalloutTone.warning);
    });
    testWidgets('arrastar pela alça troca a ordem', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois'), Block('c', BlockType.paragraph, text: 'três')]);
      await pumpEditor(tester);
      final g = await tester.startGesture(tester.getCenter(find.byTooltip('Opções do bloco 1')));
      await tester.pump(const Duration(milliseconds: 600));
      await g.moveBy(const Offset(0, 140));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(body().map((b) => b.text).toList(), isNot(['um', 'dois', 'três']));
      expect(body().length, 3);
    });
    testWidgets('o + de um bloco abre a lista e insere logo abaixo', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois')]);
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Inserir bloco depois de Parágrafo 1'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Divisor'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Divisor'));
      await tester.pumpAndSettle();
      expect(body().map((b) => b.type), [BlockType.paragraph, BlockType.divider, BlockType.paragraph]);
    });
    testWidgets('no celular os controles só aparecem no bloco tocado', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois')]);
      await pumpEditor(tester, size: const Size(400, 900));
      expect(find.byTooltip('Opções do bloco 1'), findsNothing);
      await tester.tap(field('um'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Opções do bloco 1'), findsOneWidget);
      expect(find.byTooltip('Opções do bloco 2'), findsNothing);
    });
  });

  group('capa, ícone e etiquetas', () {
    testWidgets('adicionar capa, trocar por uma combinação, escolher duas cores e remover', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpEditor(tester);
      await tester.tap(find.text('▭ Adicionar capa'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.cover, 'musgo');
      expect(find.byKey(const Key('cover')), findsOneWidget);
      await tester.tap(find.text('Trocar capa'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Capa Aurora'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.cover, 'mix:aurora');
      await tester.tap(find.bySemanticsLabel('início Azul'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.cover, startsWith('duo:azul:'));
      await tester.tap(find.bySemanticsLabel('Na diagonal').first);
      await tester.scrollUntilVisible(find.bySemanticsLabel('Lisa Verde'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.bySemanticsLabel('Lisa Verde'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.cover, 'solid:verde');
      await tester.scrollUntilVisible(find.bySemanticsLabel('Capa Oceano'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.bySemanticsLabel('Capa Oceano'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.cover, 'oceano');
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover capa'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.cover, '');
      expect(find.byKey(const Key('cover')), findsNothing);
      handle.dispose();
    });
    testWidgets('ícone: escolher da lista, recolher o recente, colar um emoji e recusar texto', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpEditor(tester);
      await tester.tap(find.text('☺ Adicionar ícone'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Ícone 📋'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.icon, '📋');
      await tester.tap(find.byTooltip('Trocar ícone da página'));
      await tester.pumpAndSettle();
      expect(find.text('RECENTES'), findsOneWidget);
      await tester.enterText(field('Cole qualquer emoji'), 'abc');
      await tester.tap(find.text('Usar'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.icon, '📋');
      await tester.enterText(field('Cole qualquer emoji'), 'ola 🎉 mundo');
      await tester.tap(find.text('Usar'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.icon, '🎉');
      await tester.tap(find.byTooltip('Trocar ícone da página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover ícone'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.icon, '');
      handle.dispose();
    });
    testWidgets('com capa e ícone o ícone fica pendurado na borda da capa', (tester) async {
      ws.page(pid)!.cover = 'musgo';
      ws.page(pid)!.icon = '💡';
      await pumpEditor(tester);
      final cover = tester.getRect(find.byKey(const Key('cover')));
      final icon = tester.getRect(find.byTooltip('Trocar ícone da página'));
      expect(icon.top, lessThan(cover.bottom));
      expect(icon.bottom, greaterThan(cover.bottom));
    });
    testWidgets('etiquetas: criar, escolher uma existente e remover', (tester) async {
      ws.addTag('antiga');
      await pumpEditor(tester, size: const Size(1500, 1000));
      await tester.tap(find.text('+ tag').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'nova tag'), 'Ideias');
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.tags, ['ideias']);
      await tester.tap(find.text('+ tag').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('antiga').last);
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.tags, ['ideias', 'antiga']);
      await tester.tap(find.byTooltip('Remover tag ideias'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.tags, ['antiga']);
      expect(ws.tag('ideias'), isNotNull);
    });
  });

  group('cabeçalho: exportar, zen, excluir', () {
    testWidgets('exportar copia o Markdown, o texto e o JSON', (tester) async {
      String? copied;
      mockClipboard(tester, (t) => copied = t);
      setBody([Block('a', BlockType.heading, text: 'Título', level: 1), Block('b', BlockType.paragraph, text: 'texto')]);
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Exportar página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar como Markdown'));
      await tester.pumpAndSettle();
      expect(copied, contains('# Título'));
      expect(find.text('Markdown copiado'), findsOneWidget);
      await tester.tap(find.byTooltip('Exportar página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar como JSON'));
      await tester.pumpAndSettle();
      expect(copied, contains('"app": "pindrel"'));
    });
    testWidgets('modo zen esconde o cabeçalho e a capa, e Esc ou o botão saem', (tester) async {
      ws.page(pid)!.cover = 'musgo';
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsNothing);
      expect(find.byKey(const Key('cover')), findsNothing);
      await tester.tap(find.text('Sair do zen'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    });
    testWidgets('excluir pede confirmação e manda para a lixeira', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => EditorPage(ws: ws, pageId: pid))), child: const Text('abrir')))))));
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(Toast.clear);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Excluir página'));
      await tester.pumpAndSettle();
      expect(find.text('Mover para a lixeira?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.trashed, false);
      await tester.tap(find.byTooltip('Excluir página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover para a lixeira').last);
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.trashed, true);
      expect(find.text('abrir'), findsOneWidget);
      expect(find.text('Movida para a lixeira'), findsOneWidget);
    });
    testWidgets('com a lixeira desligada, excluir apaga de vez', (tester) async {
      ws.saveSettings(const Settings(useTrash: false));
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => EditorPage(ws: ws, pageId: pid))), child: const Text('abrir')))))));
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(Toast.clear);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Excluir página'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir esta página?'), findsOneWidget);
      await tester.tap(find.text('Excluir definitivamente'));
      await tester.pumpAndSettle();
      expect(ws.page(pid), isNull);
    });
    testWidgets('no celular o cabeçalho junta o resto no menu "⋯"', (tester) async {
      await pumpEditor(tester, size: const Size(400, 900));
      expect(find.byTooltip('Modo zen'), findsNothing);
      await tester.tap(find.byTooltip('Mais opções da página'));
      await tester.pumpAndSettle();
      expect(find.text('Modo zen'), findsOneWidget);
      expect(find.text('Propriedades'), findsOneWidget);
      await tester.tap(find.text('Painel'));
      await tester.pumpAndSettle();
      expect(find.text('Nesta página'.toUpperCase()), findsOneWidget);
    });
  });

  group('painéis laterais', () {
    testWidgets('em tela larga ficam encostados na página e fecham pela setinha', (tester) async {
      setBody([Block('h', BlockType.heading, text: 'Capítulo um', level: 1), Block('c', BlockType.checklist, items: [ChecklistItem(id: 'i', text: 'x', done: true), ChecklistItem(id: 'j', text: 'y')])]);
      await pumpEditor(tester, size: const Size(1500, 1000));
      expect(find.text('Propriedades'), findsOneWidget);
      expect(find.text('Painel'), findsOneWidget);
      expect(find.text('NESTA PÁGINA'), findsOneWidget);
      expect(find.text('Capítulo um'), findsWidgets);
      expect(find.text('1 de 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Fechar painel'));
      await tester.pumpAndSettle();
      expect(find.text('Painel'), findsNothing);
      await tester.tap(find.byTooltip('Fechar propriedades'));
      await tester.pumpAndSettle();
      expect(find.text('Propriedades'), findsNothing);
      await tester.tap(find.byTooltip('Abrir painel'));
      await tester.pumpAndSettle();
      expect(find.text('Painel'), findsOneWidget);
    });
    testWidgets('em tela média abrem como gavetas pelas setinhas das bordas', (tester) async {
      await pumpEditor(tester, size: const Size(900, 1000));
      expect(find.text('Painel'), findsNothing);
      await tester.tap(find.byTooltip('Abrir painel'));
      await tester.pumpAndSettle();
      expect(find.text('Painel'), findsOneWidget);
      await tester.tapAt(const Offset(10, 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir propriedades'));
      await tester.pumpAndSettle();
      expect(find.text('Propriedades'), findsOneWidget);
    });
    testWidgets('o painel dobra as seções, mostra os números e fixa e duplica a página', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'uma duas três')]);
      final other = ws.newPage('Parecida');
      ws.page(pid)!.tags = ['x'];
      other.tags = ['x'];
      ws.tags.add(ws.addTag('x')!);
      await pumpEditor(tester, size: const Size(1500, 1000));
      expect(find.text('palavras'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      await tester.tap(find.text('DETALHES'));
      await tester.pumpAndSettle();
      expect(find.text('palavras'), findsNothing);
      await tester.tap(find.text('Fixar página'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.pinned, true);
      expect(find.text('Desafixar página'), findsOneWidget);
      await tester.tap(find.text('Duplicar página'));
      await tester.pumpAndSettle();
      expect(ws.pages.length, 3);
    });
    testWidgets('relacionadas abrem a outra página', (tester) async {
      final t = ws.addTag('x')!;
      ws.page(pid)!.tags = [t.id];
      ws.newPage('Parecida').tags = [t.id];
      await pumpEditor(tester, size: const Size(1500, 1000));
      await tester.tap(find.text('Parecida'));
      await tester.pumpAndSettle();
      expect(find.text('Parecida'), findsWidgets);
    });
  });

  group('lixeira e páginas que somem', () {
    testWidgets('página na lixeira só pode ser lida e restaurada', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'fica')]);
      ws.trash(pid);
      await pumpEditor(tester);
      expect(find.text('Esta página está na lixeira e não pode ser editada.'), findsOneWidget);
      expect(find.byKey(const Key('draft')), findsNothing);
      expect(find.byTooltip('Opções do bloco 1'), findsNothing);
      expect(find.text('+ tag'), findsNothing);
      final f = tester.widget<TextField>(field('fica'));
      expect(f.readOnly, true);
      await tester.tap(find.text('Restaurar'));
      await tester.pumpAndSettle();
      expect(ws.page(pid)!.trashed, false);
      expect(find.byKey(const Key('draft')), findsOneWidget);
    });
    testWidgets('uma página que sumiu enquanto estava aberta não quebra', (tester) async {
      await pumpEditor(tester);
      ws.deleteForever(pid);
      await tester.pumpAndSettle();
      expect(find.text('Esta página não existe mais.'), findsOneWidget);
    });
  });

  group('telas pequenas e descuidadas', () {
    testWidgets('320 px e texto grande, com todos os tipos de bloco', (tester) async {
      ws.page(pid)!.cover = 'musgo';
      ws.page(pid)!.icon = '💡';
      setBody([for (final t in BlockType.values) makeBlock(t)]);
      await pumpEditor(tester, size: const Size(320, 640), textScale: 2);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 14; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
    testWidgets('as larguras de tela mais comuns não estouram', (tester) async {
      setBody([Block('h', BlockType.heading, text: 'Título', level: 1), makeBlock(BlockType.checklist), makeBlock(BlockType.table), makeBlock(BlockType.code), makeBlock(BlockType.callout)]);
      for (final w in [320.0, 360.0, 400.0, 480.0, 600.0, 768.0, 840.0, 1024.0, 1340.0, 1800.0]) {
        await pumpEditor(tester, size: Size(w, 900));
        expect(tester.takeException(), isNull, reason: 'largura $w');
      }
    });
    testWidgets('texto enorme e estranho num bloco', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: '')]);
      await pumpEditor(tester);
      await tester.enterText(find.byType(TextField).at(1), 'a' * (maxText + 500));
      await tester.pump();
      expect(body().first.text!.length, maxText);
      await tester.enterText(find.byType(TextField).at(1), '😀 日本語 \u202E\u0000 <script>');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
    testWidgets('trezentos blocos: só os que aparecem são montados', (tester) async {
      setBody([for (var i = 0; i < 300; i++) Block('p$i', BlockType.paragraph, text: 'linha $i')]);
      await pumpEditor(tester);
      expect(find.byType(TextField).evaluate().length, lessThan(40));
    });
    testWidgets('toques repetidos e fora de ordem: abrir e fechar menus em sequência', (tester) async {
      setBody([Block('a', BlockType.paragraph, text: 'um')]);
      await pumpEditor(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Opções do bloco 1'));
        await tester.pump();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Modo zen'));
      await tester.tap(find.byTooltip('Modo zen'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
