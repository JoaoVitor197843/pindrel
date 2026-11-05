export type TokenKind = 'comment' | 'string' | 'keyword' | 'number' | 'text'
export interface Token {
  t: string
  k: TokenKind
}

const KEYWORDS: Record<string, string[]> = {
  python: ['def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'in', 'not', 'and', 'or', 'import', 'from', 'as', 'with', 'try', 'except', 'finally', 'raise', 'lambda', 'None', 'True', 'False', 'pass', 'yield', 'async', 'await'],
  javascript: ['function', 'const', 'let', 'var', 'return', 'if', 'else', 'for', 'while', 'class', 'new', 'import', 'from', 'export', 'default', 'async', 'await', 'try', 'catch', 'throw', 'null', 'undefined', 'true', 'false', 'switch', 'case', 'break', 'continue'],
  go: ['func', 'package', 'import', 'return', 'if', 'else', 'for', 'range', 'var', 'const', 'type', 'struct', 'interface', 'go', 'defer', 'chan', 'select', 'switch', 'case', 'nil', 'true', 'false'],
  rust: ['fn', 'let', 'mut', 'pub', 'use', 'mod', 'struct', 'enum', 'impl', 'trait', 'match', 'if', 'else', 'for', 'while', 'loop', 'return', 'async', 'await', 'self', 'true', 'false', 'const'],
  sql: ['select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create', 'table', 'join', 'left', 'inner', 'on', 'group', 'by', 'order', 'limit', 'and', 'or', 'not', 'null', 'as'],
  bash: ['if', 'then', 'else', 'fi', 'for', 'do', 'done', 'while', 'case', 'esac', 'function', 'echo', 'export', 'cd', 'exit'],
  json: ['true', 'false', 'null'],
}
KEYWORDS.typescript = [...KEYWORDS.javascript, 'interface', 'type', 'enum', 'implements', 'public', 'private', 'readonly']

const LINE_COMMENT: Record<string, string> = { python: '#', bash: '#', javascript: '//', typescript: '//', go: '//', rust: '//', sql: '--' }

/** Highlighting never looks past this many characters: a huge paste must not freeze typing. */
export const MAX_HIGHLIGHT = 20_000

/**
 * A small single-pass tokenizer: comments, strings, numbers and keywords. Not a parser: an unclosed string or comment
 * simply runs to the end of the line (or text). The concatenation of every `t` is always exactly the input.
 */
export function highlight(code: string, lang: string): Token[] {
  const head = code.slice(0, MAX_HIGHLIGHT)
  const rest = code.slice(MAX_HIGHLIGHT)
  const words = new Set(KEYWORDS[lang] ?? [])
  const lineComment = LINE_COMMENT[lang]
  const out: Token[] = []
  const push = (t: string, k: TokenKind) => {
    if (!t) return
    const last = out[out.length - 1]
    if (last && last.k === k) last.t += t
    else out.push({ t, k })
  }
  let i = 0
  while (i < head.length) {
    const c = head[i]
    if (lineComment && head.startsWith(lineComment, i)) {
      const end = head.indexOf('\n', i)
      const stop = end === -1 ? head.length : end
      push(head.slice(i, stop), 'comment')
      i = stop
    } else if (lang !== 'texto' && head.startsWith('/*', i) && lang !== 'python' && lang !== 'bash') {
      const end = head.indexOf('*/', i + 2)
      const stop = end === -1 ? head.length : end + 2
      push(head.slice(i, stop), 'comment')
      i = stop
    } else if (lang !== 'texto' && (c === '"' || c === "'" || c === '`')) {
      let j = i + 1
      while (j < head.length && head[j] !== c && (head[j] !== '\n' || c === '`')) j += head[j] === '\\' ? 2 : 1
      const stop = Math.min(head.length, head[j] === c ? j + 1 : j)
      push(head.slice(i, stop), 'string')
      i = stop
    } else if (lang !== 'texto' && /[0-9]/.test(c) && !/[A-Za-z_]/.test(head[i - 1] ?? '')) {
      let j = i + 1
      while (j < head.length && /[0-9._]/.test(head[j])) j++
      push(head.slice(i, j), 'number')
      i = j
    } else if (/[A-Za-z_]/.test(c)) {
      let j = i + 1
      while (j < head.length && /[A-Za-z0-9_]/.test(head[j])) j++
      const word = head.slice(i, j)
      push(word, words.has(lang === 'sql' ? word.toLowerCase() : word) ? 'keyword' : 'text')
      i = j
    } else {
      push(c, 'text')
      i++
    }
  }
  push(rest, 'text')
  return out
}
