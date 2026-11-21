// The insert menu can be narrowed by typing, even by someone who spells it differently.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/presentation/widgets/insert_menu.dart';

void main() {
  Future<InsertChoice?> open(WidgetTester t) {
    final f = showInsertMenu(t.element(find.byType(Scaffold)));
    return f;
  }

  testWidgets('typing narrows the list; accents and case do not matter; Enter takes the first', (t) async {
    await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: SizedBox())));
    InsertChoice? got;
    final f = open(t).then((c) => got = c);
    await t.pumpAndSettle();
    expect(find.text('Tabela'), findsNothing, reason: 'far down the list, off screen: why the filter exists');
    await t.enterText(find.byKey(const Key('insert-filter')), 'TÁBELA');
    await t.pumpAndSettle();
    expect(find.text('Tabela'), findsOneWidget, reason: 'case and accents do not matter');
    await t.enterText(find.byKey(const Key('insert-filter')), 'planilha');
    await t.pumpAndSettle();
    expect(find.text('Tabela'), findsOneWidget, reason: 'a synonym finds it');
    expect(find.text('Texto'), findsNothing);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await f;
    expect(got?.type, BlockType.table);
  });

  testWidgets('nothing matches: says so, and does not crash on spaces or a long text', (t) async {
    await t.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: SizedBox())));
    open(t);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('insert-filter')), '   ');
    await t.pumpAndSettle();
    expect(find.text('Texto'), findsOneWidget, reason: 'only spaces: everything stays');
    await t.enterText(find.byKey(const Key('insert-filter')), 'zzzz ' * 8);
    await t.pumpAndSettle();
    expect(find.textContaining('Nenhum bloco'), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('insert-filter')), findsOneWidget, reason: 'Enter with no match leaves the menu open');
  });
}
