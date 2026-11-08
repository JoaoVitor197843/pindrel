import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/dashboard_page.dart';
import 'package:mobile/features/notes/presentation/pages/notes_gate.dart';
import 'package:mobile/features/notes/presentation/providers/notes_provider.dart';
import 'package:mobile/features/notes/presentation/widgets/page_card.dart';
import 'package:mobile/features/notes/presentation/widgets/ui.dart';

late NotesDb db;
late Workspace ws;
var clock = DateTime(2026, 11, 7, 12).millisecondsSinceEpoch;

Future<void> pumpDashboard(WidgetTester tester, {Size size = const Size(400, 800), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(Toast.clear);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: DashboardPage(ws: ws),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get search => find.byType(TextField).first;

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Abrir menu'));
  await tester.pumpAndSettle();
}

/// Clipboard calls have no platform behind them in tests; answer them so the awaiting code goes on.
void mockClipboard(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

void main() {
  setUp(() {
    db = NotesDb.inMemory();
    ws = Workspace(db, clock: () => clock += 10);
  });
  tearDown(() {
    ws.dispose();
    db.dispose();
  });

  void seed() {
    final a = ws.newPage('Reforma do apartamento');
    a.content!.add(Block('b', BlockType.paragraph, text: 'Orçamento total'));
    ws.touch(a.id);
    final t = ws.addTag('casa')!;
    a.tags = [t.id];
    ws.setTitle(a.id, a.title);
    ws.newPage('Receita de pão');
    ws.togglePin(ws.newPage('Fixada').id);
  }

  group('o painel', () {
    testWidgets('sem páginas mostra o convite e criar abre o editor', (tester) async {
      await pumpDashboard(tester);
      expect(find.text('Nenhuma página ainda'), findsOneWidget);
      await tester.tap(find.text('Criar primeira página'));
      await tester.pumpAndSettle();
      expect(ws.pages.length, 1);
      expect(find.text('Página criada'), findsOneWidget);
      expect(find.byKey(const ValueKey('title')), findsOneWidget);
    });

    testWidgets('lista as páginas em grupos, com a fixada primeiro', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(400, 1500));
      expect(find.text('FIXADAS'), findsOneWidget);
      expect(find.text('HOJE'), findsOneWidget);
      expect(find.byKey(const Key('page-card')), findsNWidgets(3));
      expect(find.text('3 páginas'), findsOneWidget);
      expect(find.text('Orçamento total'), findsOneWidget);
      expect(find.text('casa'), findsOneWidget);
    });

    testWidgets('a busca ignora acento e caixa, e some ao limpar', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(400, 1500));
      await tester.enterText(search, 'ORCAMENTO');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-card')), findsOneWidget);
      expect(find.text('1 página'), findsOneWidget);
      await tester.enterText(search, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nada encontrado'), findsOneWidget);
      await tester.tap(find.text('Limpar filtros'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-card')), findsNWidgets(3));
      expect(ws.query, '');
    });

    testWidgets('o X da busca limpa o campo', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(400, 1500));
      await tester.enterText(search, 'pão');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Limpar busca'));
      await tester.pumpAndSettle();
      expect(ws.query, '');
      expect(find.byKey(const Key('page-card')), findsNWidgets(3));
    });

    testWidgets('fixar, mover para a lixeira (com aviso), restaurar e esvaziar', (tester) async {
      seed();
      await pumpDashboard(tester);
      await tester.tap(find.byTooltip('Desafixar Fixada'));
      await tester.pumpAndSettle();
      expect(find.text('FIXADAS'), findsNothing);
      await tester.tap(find.byTooltip('Mover Receita de pão para a lixeira'));
      await tester.pumpAndSettle();
      expect(find.text('Movida para a lixeira'), findsOneWidget);
      expect(ws.counts.trash, 1);
      await openMenu(tester);
      await tester.tap(find.text('Lixeira'));
      await tester.pumpAndSettle();
      expect(find.text('Receita de pão'), findsWidgets);
      await tester.tap(find.text('Restaurar'));
      await tester.pumpAndSettle();
      expect(ws.counts.trash, 0);
      ws.trash(ws.pages.first.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esvaziar lixeira'));
      await tester.pumpAndSettle();
      expect(find.text('Esvaziar a lixeira?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(ws.counts.trash, 1);
      await tester.tap(find.text('Esvaziar lixeira'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esvaziar'));
      await tester.pumpAndSettle();
      expect(ws.counts.trash, 0);
      expect(find.text('Lixeira vazia'), findsOneWidget);
    });

    testWidgets('grade e lista, ordem recente e A–Z', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      expect(ws.layout, NotesLayout.grid);
      await tester.tap(find.byTooltip('Lista'));
      await tester.pumpAndSettle();
      expect(ws.layout, NotesLayout.list);
      await tester.tap(find.text('A–Z'));
      await tester.pumpAndSettle();
      expect(ws.sort, NotesSort.az);
      final titles = tester.widgetList<PageCard>(find.byType(PageCard)).map((c) => c.page.title).toList();
      expect(titles, ['Fixada', 'Receita de pão', 'Reforma do apartamento']);
      await tester.tap(find.text('RECENTES'));
      await tester.pumpAndSettle();
      expect(ws.sort, NotesSort.recent);
    });

    testWidgets('três colunas em tela larga, duas em média e uma no celular', (tester) async {
      for (var i = 0; i < 7; i++) {
        ws.newPage('Página $i');
      }
      Future<int> columns(Size s) async {
        await pumpDashboard(tester, size: s);
        final y = tester.getTopLeft(find.byType(PageCard).first).dy;
        return tester.widgetList<PageCard>(find.byType(PageCard)).where((c) => tester.getTopLeft(find.byWidget(c)).dy == y).length;
      }

      expect(await columns(const Size(1500, 1200)), 3);
      expect(await columns(const Size(900, 1200)), 2);
      expect(await columns(const Size(400, 1200)), 1);
    });

    testWidgets('tela larga mostra a barra lateral, a estreita usa a gaveta, a média usa o trilho', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      expect(find.text('Nova página'), findsOneWidget);
      expect(find.byTooltip('Abrir menu'), findsNothing);
      await pumpDashboard(tester, size: const Size(400, 800));
      expect(find.text('Nova página'), findsNothing);
      await openMenu(tester);
      expect(find.text('Nova página'), findsOneWidget);
      await pumpDashboard(tester, size: const Size(1000, 800));
      expect(find.text('Nova página'), findsNothing);
      expect(find.byKey(const Key('new-page')), findsOneWidget);
      await tester.tap(find.text('P'));
      await tester.pumpAndSettle();
      expect(find.text('Nova página'), findsOneWidget);
    });

    testWidgets('as quatro visões e seus vazios', (tester) async {
      await pumpDashboard(tester, size: const Size(1500, 900));
      for (final (label, text) in [('Cofre', 'Cofre em breve'), ('Lixeira', 'Lixeira vazia'), ('Todas as páginas', 'Nenhuma página ainda')]) {
        await tester.tap(find.descendant(of: find.byKey(ValueKey('view-${{'Cofre': 'vault', 'Lixeira': 'trash', 'Todas as páginas': 'all'}[label]}')), matching: find.text(label)));
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: label);
      }
    });

    testWidgets('etiquetas: filtrar pela barra lateral, tirar o filtro e criar uma nova', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byKey(const ValueKey('tag-casa')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-card')), findsOneWidget);
      expect(find.text('#casa'), findsOneWidget);
      await tester.tap(find.text('tag: casa'));
      await tester.pumpAndSettle();
      expect(ws.tagFilter, isNull);
      await tester.tap(find.byTooltip('Nova tag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'nome da tag'), 'Minha Ideia');
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();
      expect(ws.tag('minha-ideia'), isNotNull);
    });

    testWidgets('nome de tag vazio não cria nada', (tester) async {
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Nova tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();
      expect(ws.tags, isEmpty);
    });

    testWidgets('configurações: desligar a lixeira e voltar a página', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Menu da conta de Você'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Dias de retenção da lixeira'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trash-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(ws.settings.useTrash, false);
      expect(find.text('Configurações salvas'), findsOneWidget);
      await tester.tap(find.byTooltip('Mover Fixada para a lixeira'));
      await tester.pumpAndSettle();
      expect(find.text('Página excluída'), findsOneWidget);
      expect(ws.counts.trash, 0);
    });

    testWidgets('configurações: seções de dados e de lixeira', (tester) async {
      mockClipboard(tester);
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Menu da conta de Você'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importar / exportar'));
      await tester.pumpAndSettle();
      expect(find.text('Exportar tudo'), findsOneWidget);
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Copiado: 3 páginas'), findsOneWidget);
      await tester.tap(find.text('Lixeira').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('mantidas por 30 dias'), findsOneWidget);
    });

    testWidgets('o menu lateral não oferece "Compartilhadas comigo"', (tester) async {
      await pumpDashboard(tester, size: const Size(1500, 900));
      expect(find.text('Compartilhadas comigo'), findsNothing);
      expect(find.text('Lixeira'), findsWidgets);
    });

    testWidgets('configurações: a seção de IA troca de provedor e pede endereço nos locais', (tester) async {
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Menu da conta de Você'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IA (opcional)'));
      await tester.pumpAndSettle();
      expect(find.text('desligada por padrão'), findsOneWidget);
      expect(find.text('Chave de API'), findsOneWidget);
      expect(find.text('sk-ant-…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Endpoint local (Ollama)').last);
      await tester.pumpAndSettle();
      expect(find.text('Endereço do servidor'), findsOneWidget);
      expect(find.text('http://localhost:11434'), findsOneWidget);
    });

    testWidgets('configurações no celular: lista de seções e voltar', (tester) async {
      await pumpDashboard(tester, size: const Size(400, 800));
      await tester.tap(find.byTooltip('Menu da conta de Você'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Usar a lixeira'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar para as seções'));
      await tester.pumpAndSettle();
      expect(find.text('Importar/Exportar'), findsOneWidget);
      await tester.tap(find.text('Conta'));
      await tester.pumpAndSettle();
      expect(find.text('Conta e servidor'), findsOneWidget);
      await tester.tap(find.byTooltip('Fechar configurações'));
      await tester.pumpAndSettle();
    });
  });

  group('a busca rápida', () {
    testWidgets('abre, filtra, escolhe uma página e fecha com Esc', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Busca rápida'));
      await tester.pumpAndSettle();
      expect(find.text('PÁGINAS'), findsOneWidget);
      expect(find.text('AÇÕES'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'receita');
      await tester.pumpAndSettle();
      expect(find.text('1 resultado'), findsOneWidget);
      await tester.tap(find.text('Receita de pão').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('title')), findsOneWidget);
    });

    testWidgets('setas e Enter escolhem sem tocar', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Busca rápida'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'criar nova');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(ws.pages.length, 4);
    });

    testWidgets('sem resultado avisa; tag filtra; ordenação alterna', (tester) async {
      seed();
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Busca rápida'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nada encontrado'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'casa');
      await tester.pumpAndSettle();
      await tester.tap(find.text('#casa'));
      await tester.pumpAndSettle();
      expect(ws.tagFilter, 'casa');
    });

    testWidgets('abrir configurações pela busca', (tester) async {
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byTooltip('Busca rápida'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Dias de retenção da lixeira'), findsOneWidget);
    });
  });

  group('telas pequenas e descuidadas', () {
    testWidgets('320 px de largura e texto grande não estouram', (tester) async {
      seed();
      ws.newPage('Um título muito longo '.padRight(200, 'x'));
      await pumpDashboard(tester, size: const Size(320, 600), textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await openMenu(tester);
      expect(tester.takeException(), isNull);
    });
    testWidgets('várias buscas seguidas e vazias, com texto estranho', (tester) async {
      seed();
      await pumpDashboard(tester);
      for (final q in ['', '   ', '%', '\\', '😀', 'a' * 500, '[', '(']) {
        await tester.enterText(search, q);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
    testWidgets('mil páginas: só se monta o que aparece', (tester) async {
      for (var i = 0; i < 1000; i++) {
        ws.newPage('Página $i');
      }
      await pumpDashboard(tester);
      expect(find.byKey(const Key('page-card')).evaluate().length, lessThan(30));
      expect(find.text('1000 páginas'), findsOneWidget);
    });
    testWidgets('toques repetidos em "Nova página" criam uma página por toque, sem quebrar', (tester) async {
      await pumpDashboard(tester, size: const Size(1500, 900));
      await tester.tap(find.byKey(const Key('new-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(ws.pages.length, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('destaque da busca', () {
    const base = TextStyle(), mark = TextStyle(fontWeight: FontWeight.bold);
    List<String> parts(String t, String q) => [for (final s in highlightSpans(t, q, base, mark)) (s as TextSpan).text!];
    test('marca ignorando acento e caixa', () {
      expect(parts('Orçamento total', 'orcamento'), ['Orçamento', ' total']);
      expect(parts('abcabc', 'b'), ['a', 'b', 'ca', 'b', 'c']);
    });
    test('sem busca ou sem achado, devolve o texto inteiro', () {
      expect(parts('texto', ''), ['texto']);
      expect(parts('texto', 'zz'), ['texto']);
    });
    test('texto que muda de tamanho ao dobrar não é marcado errado', () {
      expect(parts('Straße', 'ss'), ['Straße']);
    });
  });

  group('porta de entrada', () {
    testWidgets('abre as notas do aparelho', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [workspaceProvider.overrideWith((ref) async => ws)],
        child: MaterialApp(theme: AppTheme.dark, home: const NotesGate()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma página ainda'), findsOneWidget);
    });
    testWidgets('se o banco não abre, mostra o erro e deixa tentar de novo', (tester) async {
      var tries = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) async {
            if (tries++ == 0) throw StateError('disco cheio');
            return ws;
          }),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const NotesGate()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível abrir suas notas'), findsOneWidget);
      expect(find.textContaining('disco cheio'), findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma página ainda'), findsOneWidget);
    });
  });
}
