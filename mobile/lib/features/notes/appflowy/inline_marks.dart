// The text of a block is stored with markdown-style markers (`**bold**`,
// `*italic*`, `__underline__`, `~~strike~~`, `==highlight==`, `` `code` ``,
// `[text](url)`), the very same string the web keeps. The editor works on a
// Delta (runs of text with attributes), so this file is the whole bridge.
//
// It is a port of `web/src/lib/stores/inlineParse.ts` (the reader) and
// `web/src/lib/components/editor/rich/runs.ts` (the writer). Keep them in step:
// a text must mean the same on both clients, nesting, word boundaries and all.

import 'package:appflowy_editor/appflowy_editor.dart';

/// The attribute the editor keeps a highlight under (its own `AppFlowyRichTextKeys.backgroundColor`).
const highlightKey = 'bg_color';

/// Colour the editor paints behind a `==highlight==` run (an ARGB hex string, as the editor stores it).
const highlightColor = '0x66E5C07B';

class Marks {
  const Marks({this.bold = false, this.italic = false, this.underline = false, this.strike = false, this.highlight = false, this.code = false, this.link});
  final bool bold, italic, underline, strike, highlight, code;

  /// The address of a link.
  final String? link;

  Marks copyWith({bool? bold, bool? italic, bool? underline, bool? strike, bool? highlight, bool? code, String? link}) => Marks(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    highlight: highlight ?? this.highlight,
    code: code ?? this.code,
    link: link ?? this.link,
  );

  bool get any => bold || italic || underline || strike || highlight || link != null;

  @override
  bool operator ==(Object other) => other is Marks && bold == other.bold && italic == other.italic && underline == other.underline && strike == other.strike && highlight == other.highlight && code == other.code && link == other.link;

  @override
  int get hashCode => Object.hash(bold, italic, underline, strike, highlight, code, link);
}

class Run {
  Run(this.text, this.marks);
  String text;
  final Marks marks;
}

/// Joins neighbours that carry the same marks and drops empty ones.
List<Run> mergeRuns(List<Run> runs) {
  final out = <Run>[];
  for (final r in runs) {
    if (r.text.isEmpty) continue;
    if (out.isNotEmpty && out.last.marks == r.marks) {
      out.last.text += r.text;
    } else {
      out.add(Run(r.text, r.marks));
    }
  }
  return out;
}

const _delims = ['**', '__', '~~', '==', '*', '_'];

final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _space = RegExp(r'\s');
final _code = RegExp(r'`[^`\n]+`');
/// What the reader accepts as a link address: anything else would be written but never read back as a link.
final _safeHref = RegExp(r'^(?:https?://|mailto:)[^\s)]+$');
final _link = RegExp(r'\[([^\]\n]+)\]\(((?:https?://|mailto:)[^\s)]+)\)');

/// Steps one read may take before it gives up and leaves the rest as plain text (a text made to be slow).
const _budget = 300000;
const _maxDepth = 40;

Marks _with(Marks m, String d) => switch (d) {
  '**' => m.copyWith(bold: true),
  '__' => m.copyWith(underline: true),
  '~~' => m.copyWith(strike: true),
  '==' => m.copyWith(highlight: true),
  _ => m.copyWith(italic: true),
};

/// Reads the markers in [s] as runs of text with marks, nesting included.
List<Run> parseInline(String s) {
  if (!RegExp(r'[*_~=`\[]').hasMatch(s)) return s.isEmpty ? [] : [Run(s, const Marks())];
  final n = s.length;
  var steps = 0;
  final memo = <int, int>{};

  bool isWord(String c) => c.isNotEmpty && _word.hasMatch(c);
  bool isSpace(String c) => _space.hasMatch(c);
  String at(int i) => i >= 0 && i < n ? s[i] : '';

  int runBefore(int i, String ch) {
    var k = 0;
    while (i - 1 - k >= 0 && s[i - 1 - k] == ch) {
      k++;
    }
    return k;
  }

  int runAt(int i, String ch) {
    var k = 0;
    while (i + k < n && s[i + k] == ch) {
      k++;
    }
    return k;
  }

  bool isOpener(int i, String d) {
    if (!s.startsWith(d, i)) return false;
    final next = at(i + d.length);
    if (next.isEmpty || isSpace(next)) return false;
    final ch = d[0];
    final prev = at(i - 1);
    if (d == '~~') return next != '~' && prev != '~';
    if (d == '==') return next != '=' && prev != '=' && !isWord(prev);
    if (ch == '*') return !isWord(prev) && runBefore(i, '*') % 2 == 0;
    return !isWord(prev) && runBefore(i, '_') % 2 == 0 && (d == '__' || runAt(i, '_') == 1);
  }

  bool isCloser(int i, String d) {
    if (!s.startsWith(d, i) || i == 0 || isSpace(s[i - 1])) return false;
    final ch = d[0];
    if (d == '~~') return s[i - 1] != '~' && at(i + 2) != '~';
    if (d == '==') return s[i - 1] != '=' && at(i + 2) != '=' && !isWord(at(i + 2));
    final run = runAt(i, ch);
    if (ch == '*') return d == '**' ? run >= 2 : run % 2 == 1;
    if (isWord(at(i + d.length))) return false;
    return d == '__' ? run >= 2 : run % 2 == 1;
  }

  late int Function(int, String, int) findEnd;
  findEnd = (int i, String d, int depth) {
    final key = i * 8 + _delims.indexOf(d);
    final known = memo[key];
    if (known != null) return known;
    var result = -1;
    if (depth < _maxDepth && steps < _budget) {
      final inner = i + d.length;
      var j = inner;
      scan:
      while (j < n && steps++ < _budget) {
        final c = s[j];
        if (c == '\n') break; // a mark never crosses a line
        if (c == '`') {
          final m = _code.matchAsPrefix(s, j);
          if (m != null) {
            j += m.group(0)!.length;
            continue;
          }
        } else if (c == '[') {
          final m = _link.matchAsPrefix(s, j);
          if (m != null) {
            j += m.group(0)!.length;
            continue;
          }
        }
        if (j > inner && isCloser(j, d)) {
          result = j;
          break;
        }
        for (final o in _delims) {
          if (s.startsWith(o, j) && isOpener(j, o)) {
            final e = findEnd(j, o, depth + 1);
            if (e >= 0) {
              j = e + o.length;
              continue scan;
            }
          }
        }
        j++;
      }
    }
    memo[key] = result;
    return result;
  };

  final out = <Run>[];
  void emit(int from, int to, Marks marks, int depth) {
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      out.add(Run(buf.toString(), marks));
      buf.clear();
    }

    var i = from;
    while (i < to) {
      final c = s[i];
      if (c == '`') {
        final m = _code.matchAsPrefix(s, i);
        if (m != null && i + m.group(0)!.length <= to) {
          flush();
          final t = m.group(0)!;
          out.add(Run(t.substring(1, t.length - 1), marks.copyWith(code: true)));
          i += t.length;
          continue;
        }
      } else if (c == '[') {
        final m = _link.matchAsPrefix(s, i);
        if (m != null && i + m.group(0)!.length <= to) {
          flush();
          emit(i + 1, i + 1 + m.group(1)!.length, marks.copyWith(link: m.group(2)), depth + 1);
          i += m.group(0)!.length;
          continue;
        }
      }
      var opened = false;
      for (final d in _delims) {
        if (!isOpener(i, d)) continue;
        final e = findEnd(i, d, depth);
        if (e < 0 || e + d.length > to) continue;
        flush();
        emit(i + d.length, e, _with(marks, d), depth + 1);
        i = e + d.length;
        opened = true;
        break;
      }
      if (!opened) {
        buf.write(s[i]);
        i++;
      }
    }
    flush();
  }

  emit(0, n, const Marks(), 0);
  return mergeRuns(out);
}

// outermost first, so neighbours that share a mark stay inside one pair of markers
const _order = ['link', 'bold', 'underline', 'strike', 'highlight', 'italic'];
const _open = {'bold': '**', 'underline': '__', 'strike': '~~', 'highlight': '==', 'italic': '*'};

Object? _value(Marks m, String k) => switch (k) {
  'link' => m.link,
  'bold' => m.bold ? true : null,
  'underline' => m.underline ? true : null,
  'strike' => m.strike ? true : null,
  'highlight' => m.highlight ? true : null,
  _ => m.italic ? true : null,
};

/// The marks two neighbours share.
Marks _shared(Marks? a, Marks b) {
  if (a == null) return const Marks();
  return Marks(
    bold: a.bold && b.bold,
    italic: a.italic && b.italic,
    underline: a.underline && b.underline,
    strike: a.strike && b.strike,
    highlight: a.highlight && b.highlight,
    link: a.link != null && a.link == b.link ? a.link : null,
  );
}

/// Splits on line breaks keeping each one as its own part (JS `split(/(\n)/)`).
List<String> _splitLines(String t) {
  final out = <String>[];
  var from = 0;
  for (var i = 0; i < t.length; i++) {
    if (t[i] != '\n') continue;
    out.add(t.substring(from, i));
    out.add('\n');
    from = i + 1;
  }
  out.add(t.substring(from));
  return out;
}

/// Markers must hug the words and stay inside one line, so spaces and line breaks at the edge of a marked stretch move
/// out of it. A space between two runs that share the mark stays inside (`**a *b* c**` is one bold stretch).
List<Run> _hugging(List<Run> runs) {
  final out = <Run>[];
  for (var idx = 0; idx < runs.length; idx++) {
    final r = runs[idx];
    if (!r.marks.any || r.marks.code) {
      out.add(r);
      continue;
    }
    final prev = idx > 0 ? runs[idx - 1].marks : null;
    final next = idx + 1 < runs.length ? runs[idx + 1].marks : null;
    final parts = _splitLines(r.text);
    for (var k = 0; k < parts.length; k++) {
      final part = parts[k];
      if (part == '\n') {
        out.add(Run(part, const Marks()));
        continue;
      }
      if (part.isEmpty) continue;
      final lead = k == 0 ? _shared(prev, r.marks) : const Marks();
      final trail = k == parts.length - 1 ? _shared(next, r.marks) : const Marks();
      final core = part.trim();
      if (core.isEmpty) {
        // only spaces: marked when both sides keep the mark going
        out.add(Run(
          part,
          Marks(
            bold: lead.bold && trail.bold,
            italic: lead.italic && trail.italic,
            underline: lead.underline && trail.underline,
            strike: lead.strike && trail.strike,
            highlight: lead.highlight && trail.highlight,
            link: lead.link != null && lead.link == trail.link ? lead.link : null,
          ),
        ));
        continue;
      }
      final from = part.indexOf(core);
      if (from > 0) out.add(Run(part.substring(0, from), lead));
      out.add(Run(core, r.marks));
      if (from + core.length < part.length) out.add(Run(part.substring(from + core.length), trail));
    }
  }
  return out;
}

/// Runs back to the text with markers.
String serializeRuns(List<Run> runs) {
  final out = StringBuffer();
  final open = <(String, Object)>[];
  void close(int to) {
    while (open.length > to) {
      final o = open.removeLast();
      out.write(o.$1 == 'link' ? '](${o.$2})' : _open[o.$1]);
    }
  }

  for (final r in mergeRuns(_hugging(mergeRuns(runs)))) {
    final want = <(String, Object)>[
      for (final k in _order)
        if (_value(r.marks, k) != null) (k, _value(r.marks, k)!),
    ];
    var common = 0;
    while (common < open.length && common < want.length && open[common].$1 == want[common].$1 && open[common].$2 == want[common].$2) {
      common++;
    }
    close(common);
    for (final w in want.skip(common)) {
      out.write(w.$1 == 'link' ? '[' : _open[w.$1]);
      open.add(w);
    }
    out.write(r.marks.code ? '`${r.text}`' : r.text);
  }
  close(0);
  return out.toString();
}

/// The Delta for a stored string.
Delta marksToDelta(String text) {
  final d = Delta();
  for (final r in parseInline(text)) {
    final m = r.marks;
    final a = <String, Object>{
      if (m.bold) 'bold': true,
      if (m.italic) 'italic': true,
      if (m.underline) 'underline': true,
      if (m.strike) 'strikethrough': true,
      if (m.highlight) highlightKey: highlightColor,
      if (m.code) 'code': true,
      if (m.link != null) 'href': m.link!,
    };
    d.insert(r.text, attributes: a.isEmpty ? null : a);
  }
  return d;
}

/// The stored string for a Delta (what the editor is showing).
String deltaToMarks(Delta d) {
  final runs = <Run>[];
  for (final op in d) {
    if (op is! TextInsert) continue;
    final a = op.attributes ?? const <String, dynamic>{};
    final href = a['href'];
    runs.add(Run(
      op.text,
      Marks(
        bold: a['bold'] == true,
        italic: a['italic'] == true,
        underline: a['underline'] == true,
        strike: a['strikethrough'] == true,
        highlight: a[highlightKey] != null,
        code: a['code'] == true,
        link: href is String && _safeHref.hasMatch(href) ? href : null,
      ),
    ));
  }
  return serializeRuns(runs);
}
