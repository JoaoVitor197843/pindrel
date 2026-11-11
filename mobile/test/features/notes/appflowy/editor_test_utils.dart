// Helpers to drive the rich-text body of a page the way its own API allows. The keyboard that would type into it
// (the IME) is not there in a widget test, so a test edits the document with transactions and fires the very same
// shortcut events the editor would fire.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/appflowy/page_body.dart';

PageBody bodyOf(WidgetTester t) => t.widget<PageBody>(find.byType(PageBody));
EditorState editorOf(WidgetTester t) => bodyOf(t).controller.editorState!;

/// Puts the caret in the root node [index], [offset] characters in.
Future<void> caretAt(WidgetTester t, int index, [int offset = 0]) async {
  editorOf(t).selection = Selection.collapsed(Position(path: [index], offset: offset));
  await t.pumpAndSettle();
}

/// Selects [from]..[to] of the root node [index].
Future<void> selectIn(WidgetTester t, int index, int from, int to) async {
  editorOf(t).selection = Selection.single(path: [index], startOffset: from, endOffset: to);
  await t.pumpAndSettle();
}

/// Types [text] at the end of the root node [index] (as one edit) and leaves the caret after it.
Future<void> typeAtEnd(WidgetTester t, int index, String text) async {
  final es = editorOf(t);
  final node = es.getNodeAtPath([index])!;
  final at = node.delta!.length;
  await es.apply(es.transaction..insertText(node, at, text));
  es.selection = Selection.collapsed(Position(path: [index], offset: at + text.length));
  await t.pump();
}

/// What the editor would do when [char] is typed with the caret where it is (the first shortcut that takes it).
Future<bool> pressChar(WidgetTester t, String char) async {
  final es = editorOf(t);
  for (final e in bodyOf(t).controller.characterShortcuts) {
    if (e.character == char && await e.execute(es)) {
      await t.pumpAndSettle();
      return true;
    }
  }
  return false;
}
