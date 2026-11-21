import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/appflowy/inline_marks.dart';

/// "text|attr,attr": the runs of a stored text, attributes sorted (maps cannot be compared inside records).
List<String> runs(String s) => [
  for (final op in marksToDelta(s))
    if (op is TextInsert) '${op.text}|${((op.attributes ?? const {}).keys.toList()..sort()).join(',')}',
];

void main() {
  group('marks to delta', () {
    test('plain text is one run', () {
      expect(runs('olá mundo'), ['olá mundo|']);
    });

    test('each marker becomes its attribute', () {
      expect(runs('**a**'), ['a|bold']);
      expect(runs('*a*'), ['a|italic']);
      expect(runs('_a_'), ['a|italic']);
      expect(runs('__a__'), ['a|underline']);
      expect(runs('~~a~~'), ['a|strikethrough']);
      expect(runs('==a=='), ['a|bg_color']);
      expect(runs('`a`'), ['a|code']);
      expect(runs('[a](https://x.org)'), ['a|href']);
      expect((marksToDelta('[a](https://x.org)').first as TextInsert).attributes!['href'], 'https://x.org');
    });

    test('nesting and neighbours', () {
      expect(runs('x **b *bi* b** y'), ['x |', 'b |bold', 'bi|bold,italic', ' b|bold', ' y|']);
      expect(runs('[**a**](https://x.org)'), ['a|bold,href']);
    });

    test('code keeps its content literal', () {
      expect(runs('`**a**`'), ['**a**|code']);
    });

    test('markers that do not hug words, or never close, stay as typed', () {
      for (final s in ['2 * 3 * 4', '**sem fim', '*', '**', '``', '`aberto', '[a](', '[a] (x)', '____', '~~ ~~', 'a * b', '5*3 = 15*']) {
        expect(runs(s), [if (s.isNotEmpty) '$s|'], reason: s);
      }
    });

    test('word boundaries follow the web: snake_case and a==b are plain', () {
      for (final s in ['snake_case_name', 'a==b', 'x*y*z', 'a~b', '3*4*5']) {
        expect(runs(s), ['$s|'], reason: s);
      }
    });

    test('only http, https and mailto addresses are links', () {
      expect(runs('[a](javascript:alert(1))'), ['[a](javascript:alert(1))|']);
      expect(runs('[a](mailto:x@y.org)'), ['a|href']);
    });

    test('a mark never crosses a line', () {
      expect(runs('**a\nb**'), ['**a\nb**|']);
    });

    test('a lone star does not open inside a double star', () {
      expect(runs('**a** *b*'), ['a|bold', ' |', 'b|italic']);
    });
  });

  group('delta to marks', () {
    String back(String s) => deltaToMarks(marksToDelta(s));

    test('round trips what the web writes', () {
      for (final s in ['', 'plain', '**b**', '*i*', '__u__', '~~s~~', '==h==', '`c`', '[l](https://x.org)', 'a **b** c *d* e', '**b *bi* b**', '**a *b* c**', '[*a*](https://x.org)', 'linha 1 `x` linha **2**', '**a**\n*b*']) {
        expect(back(s), s, reason: s);
      }
    });

    test('is stable: writing what was written changes nothing', () {
      for (final s in ['** a **', 'a ** b', '***x***', '**a**b**c**', '*a**b*', '[**x**](u)', '~~a ==b== c~~', '`a` `b`', '*[a](https://x.org)*', '**__~~*x*~~__**']) {
        final once = back(s);
        expect(back(once), once, reason: s);
      }
    });

    test('bold and italic together read back as both', () {
      final d = Delta()..insert('x', attributes: {'bold': true, 'italic': true});
      expect(runs(deltaToMarks(d)), ['x|bold,italic']);
    });

    test('spaces move outside the markers', () {
      final d = Delta()..insert(' dentro ', attributes: {'bold': true});
      expect(deltaToMarks(d), ' **dentro** ');
      final blank = Delta()..insert('   ', attributes: {'bold': true});
      expect(deltaToMarks(blank), '   ');
    });

    test('an address the reader would not take is dropped on the way out', () {
      final d = Delta()..insert('x', attributes: {'href': 'javascript:alert(1)'});
      expect(deltaToMarks(d), 'x');
    });

    test('a run with every attribute reads back with every attribute', () {
      final d = Delta()..insert('x', attributes: {'bold': true, 'italic': true, 'underline': true, 'strikethrough': true, highlightKey: highlightColor, 'href': 'https://x.org'});
      expect(runs(deltaToMarks(d)), ['x|bg_color,bold,href,italic,strikethrough,underline']);
    });
  });

  goldenTests();

  group('careless use', () {
    test('a huge text parses without trouble', () {
      final s = List.generate(4000, (i) => 'palavra$i **negrito** e *itálico* `cod`').join(' ');
      final sw = Stopwatch()..start();
      expect(deltaToMarks(marksToDelta(s)), s);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('thousands of unclosed markers do not blow up', () {
      final s = '*' * 5000 + '**' * 3000 + '`' * 2000 + '_' * 4000;
      final sw = Stopwatch()..start();
      expect(deltaToMarks(marksToDelta(s)), isNotNull);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('deep nesting stops at a depth and keeps the text', () {
      final s = '${'**a *b ' * 60}x${'* b** ' * 60}';
      expect(deltaToMarks(marksToDelta(s)).replaceAll(RegExp(r'[*\s]'), ''), s.replaceAll(RegExp(r'[*\s]'), ''));
    });

    test('emoji and non-latin text pass through', () {
      const s = '**olá 👋** e *日本語* `🙂`';
      expect(deltaToMarks(marksToDelta(s)), s);
    });
  });
}

// The reference is the web itself: golden/web_inline_cases.json holds what web/src/lib/stores/inlineParse.ts and
// rich/runs.ts made of 600 random texts (marker soup, links, line breaks, accents). The port must agree on all of them.
void goldenTests() {
  group('same as the web', () {
    final cases = (jsonDecode(File('test/features/notes/appflowy/golden/web_inline_cases.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

    String describe(Run r) {
      final m = r.marks;
      final k = [if (m.bold) 'bold', if (m.italic) 'italic', if (m.underline) 'underline', if (m.strike) 'strike', if (m.highlight) 'highlight', if (m.code) 'code', if (m.link != null) 'link=${m.link}'];
      return '${r.text}|${k.join(',')}';
    }

    test('reads every text into the same runs', () {
      for (final c in cases) {
        expect(parseInline(c['s'] as String).map(describe).toList(), (c['runs'] as List).cast<String>(), reason: jsonEncode(c['s']));
      }
    });

    test('writes every text back the same way', () {
      for (final c in cases) {
        expect(serializeRuns(parseInline(c['s'] as String)), c['out'], reason: jsonEncode(c['s']));
      }
    });
  });
}
