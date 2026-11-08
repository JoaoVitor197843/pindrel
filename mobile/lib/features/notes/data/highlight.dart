// A small single-pass tokenizer for code blocks: comments, strings, numbers and keywords. Not a parser: an unclosed string
// or comment simply runs to the end of the line (or text). The concatenation of every token is always exactly the input.

enum TokenKind { comment, string, keyword, number, text }

class Token {
  Token(this.text, this.kind);
  String text;
  final TokenKind kind;
}

const _js = ['function', 'const', 'let', 'var', 'return', 'if', 'else', 'for', 'while', 'class', 'new', 'import', 'from', 'export', 'default', 'async', 'await', 'try', 'catch', 'throw', 'null', 'undefined', 'true', 'false', 'switch', 'case', 'break', 'continue'];

final Map<String, Set<String>> _keywords = {
  'python': {'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'in', 'not', 'and', 'or', 'import', 'from', 'as', 'with', 'try', 'except', 'finally', 'raise', 'lambda', 'None', 'True', 'False', 'pass', 'yield', 'async', 'await'},
  'javascript': {..._js},
  'typescript': {..._js, 'interface', 'type', 'enum', 'implements', 'public', 'private', 'readonly'},
  'go': {'func', 'package', 'import', 'return', 'if', 'else', 'for', 'range', 'var', 'const', 'type', 'struct', 'interface', 'go', 'defer', 'chan', 'select', 'switch', 'case', 'nil', 'true', 'false'},
  'rust': {'fn', 'let', 'mut', 'pub', 'use', 'mod', 'struct', 'enum', 'impl', 'trait', 'match', 'if', 'else', 'for', 'while', 'loop', 'return', 'async', 'await', 'self', 'true', 'false', 'const'},
  'sql': {'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create', 'table', 'join', 'left', 'inner', 'on', 'group', 'by', 'order', 'limit', 'and', 'or', 'not', 'null', 'as'},
  'bash': {'if', 'then', 'else', 'fi', 'for', 'do', 'done', 'while', 'case', 'esac', 'function', 'echo', 'export', 'cd', 'exit'},
  'json': {'true', 'false', 'null'},
};

const _lineComment = {'python': '#', 'bash': '#', 'javascript': '//', 'typescript': '//', 'go': '//', 'rust': '//', 'sql': '--'};

/// Highlighting never looks past this many characters: a huge paste must not freeze typing.
const maxHighlight = 20000;

bool _isLetter(String c) => RegExp(r'[A-Za-z_]').hasMatch(c);
bool _isDigit(String c) => RegExp(r'[0-9]').hasMatch(c);

List<Token> highlight(String code, String lang) {
  final head = code.length > maxHighlight ? code.substring(0, maxHighlight) : code;
  final rest = code.length > maxHighlight ? code.substring(maxHighlight) : '';
  final words = _keywords[lang] ?? const <String>{};
  final lineComment = _lineComment[lang];
  final out = <Token>[];
  void push(String t, TokenKind k) {
    if (t.isEmpty) return;
    if (out.isNotEmpty && out.last.kind == k) {
      out.last.text += t;
    } else {
      out.add(Token(t, k));
    }
  }

  var i = 0;
  while (i < head.length) {
    final c = head[i];
    if (lineComment != null && head.startsWith(lineComment, i)) {
      final end = head.indexOf('\n', i);
      final stop = end == -1 ? head.length : end;
      push(head.substring(i, stop), TokenKind.comment);
      i = stop;
    } else if (lang != 'texto' && head.startsWith('/*', i) && lang != 'python' && lang != 'bash') {
      final end = head.indexOf('*/', i + 2);
      final stop = end == -1 ? head.length : end + 2;
      push(head.substring(i, stop), TokenKind.comment);
      i = stop;
    } else if (lang != 'texto' && (c == '"' || c == "'" || c == '`')) {
      var j = i + 1;
      while (j < head.length && head[j] != c && (head[j] != '\n' || c == '`')) {
        j += head[j] == r'\' ? 2 : 1;
      }
      final stop = j < head.length && head[j] == c ? j + 1 : (j > head.length ? head.length : j);
      push(head.substring(i, stop), TokenKind.string);
      i = stop;
    } else if (lang != 'texto' && _isDigit(c) && !(i > 0 && _isLetter(head[i - 1]))) {
      var j = i + 1;
      while (j < head.length && RegExp(r'[0-9._]').hasMatch(head[j])) {
        j++;
      }
      push(head.substring(i, j), TokenKind.number);
      i = j;
    } else if (_isLetter(c)) {
      var j = i + 1;
      while (j < head.length && (_isLetter(head[j]) || _isDigit(head[j]))) {
        j++;
      }
      final word = head.substring(i, j);
      push(word, words.contains(lang == 'sql' ? word.toLowerCase() : word) ? TokenKind.keyword : TokenKind.text);
      i = j;
    } else {
      push(c, TokenKind.text);
      i++;
    }
  }
  push(rest, TokenKind.text);
  return out;
}
