// Reads the markers in a block's text (`**bold**`, `*italic*`, `__underline__`, `~~strike~~`, `` `code` ``,
// `[text](url)`) as runs of text with marks, nesting included: `**__~~*x*~~__**` is one word with four marks. It is the
// one reader the page, the export and the rich-text engines share, so they can never disagree on what a text means.

export type MarkKey = 'bold' | 'italic' | 'underline' | 'strike' | 'highlight' | 'code'

export interface Marks {
  bold?: true
  italic?: true
  underline?: true
  strike?: true
  highlight?: true
  code?: true
  /** The address of a link (already checked with `safeUrl` when it was made). */
  link?: string
}

export interface Run {
  text: string
  marks: Marks
}

const same = (a: Marks, b: Marks) => a.bold === b.bold && a.italic === b.italic && a.underline === b.underline && a.strike === b.strike && a.highlight === b.highlight && a.code === b.code && a.link === b.link

/** Joins neighbours that carry the same marks and drops empty ones. */
export function mergeRuns(runs: Run[]): Run[] {
  const out: Run[] = []
  for (const r of runs) {
    if (!r.text) continue
    const last = out[out.length - 1]
    if (last && same(last.marks, r.marks)) last.text += r.text
    else out.push({ text: r.text, marks: { ...r.marks } })
  }
  return out
}

type Delim = '**' | '__' | '~~' | '==' | '*' | '_'
const DELIMS: Delim[] = ['**', '__', '~~', '==', '*', '_']
const MARK_OF: Record<Delim, 'bold' | 'underline' | 'strike' | 'highlight' | 'italic'> = { '**': 'bold', __: 'underline', '~~': 'strike', '==': 'highlight', '*': 'italic', _: 'italic' }

const WORD = /[\p{L}\p{N}]/u
const SPACE = /\s/
const CODE = /`[^`\n]+`/y
const LINK = /\[([^\]\n]+)\]\(((?:https?:\/\/|mailto:)[^\s)]+)\)/y

/** Steps one read may take before it gives up and leaves the rest as plain text (a text made to be slow). */
const BUDGET = 300_000
const MAX_DEPTH = 40

export function parseInline(s: string): Run[] {
  // nothing that could be a marker: the common case costs one scan
  if (!/[*_~=`[]/.test(s)) return s ? [{ text: s, marks: {} }] : []

  const n = s.length
  let steps = 0
  const memo = new Map<number, number>()

  const runBefore = (i: number, ch: string) => {
    let k = 0
    while (i - 1 - k >= 0 && s[i - 1 - k] === ch) k++
    return k
  }
  const runAt = (i: number, ch: string) => {
    let k = 0
    while (i + k < n && s[i + k] === ch) k++
    return k
  }

  function isOpener(i: number, d: Delim): boolean {
    if (!s.startsWith(d, i)) return false
    const next = s[i + d.length]
    if (next === undefined || SPACE.test(next)) return false
    const ch = d[0]
    const prev = i > 0 ? s[i - 1] : ''
    if (d === '~~') return next !== '~' && prev !== '~'
    // `a==b` in code-like text is not a highlight: like underscores, it must not sit inside a word
    if (d === '==') return next !== '=' && prev !== '=' && !(prev && WORD.test(prev))
    if (ch === '*') return !(prev && WORD.test(prev)) && runBefore(i, '*') % 2 === 0
    // underscores: never inside a word (snake_case_name)
    return !(prev && WORD.test(prev)) && runBefore(i, '_') % 2 === 0 && (d === '__' || runAt(i, '_') === 1)
  }

  function isCloser(i: number, d: Delim): boolean {
    if (!s.startsWith(d, i) || i === 0 || SPACE.test(s[i - 1])) return false
    const ch = d[0]
    if (d === '~~') return s[i - 1] !== '~' && s[i + 2] !== '~'
    if (d === '==') return s[i - 1] !== '=' && s[i + 2] !== '=' && !(s[i + 2] && WORD.test(s[i + 2]))
    const run = runAt(i, ch)
    if (ch === '*') return d === '**' ? run >= 2 : run % 2 === 1
    const after = s[i + d.length]
    if (after && WORD.test(after)) return false
    return d === '__' ? run >= 2 : run % 2 === 1
  }

  /** Where the closer of the marker opened at `i` begins, or -1. */
  function findEnd(i: number, d: Delim, depth: number): number {
    const key = i * 8 + DELIMS.indexOf(d)
    const known = memo.get(key)
    if (known !== undefined) return known
    let result = -1
    if (depth < MAX_DEPTH && steps < BUDGET) {
      const inner = i + d.length
      let j = inner
      scan: while (j < n && steps++ < BUDGET) {
        const c = s[j]
        // a mark never crosses a line
        if (c === '\n') break
        if (c === '`') {
          CODE.lastIndex = j
          const m = CODE.exec(s)
          if (m) {
            j += m[0].length
            continue
          }
        } else if (c === '[') {
          LINK.lastIndex = j
          const m = LINK.exec(s)
          if (m) {
            j += m[0].length
            continue
          }
        }
        if (j > inner && isCloser(j, d)) {
          result = j
          break
        }
        for (const o of DELIMS) {
          if (s.startsWith(o, j) && isOpener(j, o)) {
            const e = findEnd(j, o, depth + 1)
            if (e >= 0) {
              j = e + o.length
              continue scan
            }
          }
        }
        j++
      }
    }
    memo.set(key, result)
    return result
  }

  const out: Run[] = []
  function emit(from: number, to: number, marks: Marks, depth: number) {
    let buf = ''
    const flush = () => {
      if (buf) out.push({ text: buf, marks: { ...marks } })
      buf = ''
    }
    let i = from
    while (i < to) {
      const c = s[i]
      if (c === '`') {
        CODE.lastIndex = i
        const m = CODE.exec(s)
        if (m && i + m[0].length <= to) {
          flush()
          out.push({ text: m[0].slice(1, -1), marks: { ...marks, code: true } })
          i += m[0].length
          continue
        }
      } else if (c === '[') {
        LINK.lastIndex = i
        const m = LINK.exec(s)
        if (m && i + m[0].length <= to) {
          flush()
          emit(i + 1, i + 1 + m[1].length, { ...marks, link: m[2] }, depth + 1)
          i += m[0].length
          continue
        }
      }
      let opened = false
      for (const d of DELIMS) {
        if (!isOpener(i, d)) continue
        const e = findEnd(i, d, depth)
        if (e < 0 || e + d.length > to) continue
        flush()
        emit(i + d.length, e, { ...marks, [MARK_OF[d]]: true }, depth + 1)
        i = e + d.length
        opened = true
        break
      }
      if (!opened) buf += s[i++]
    }
    flush()
  }
  emit(0, n, {}, 0)
  return mergeRuns(out)
}

// outermost first, so neighbours that share a mark stay inside one pair of tags or markers
const ORDER = ['link', 'bold', 'underline', 'strike', 'highlight', 'italic'] as const
const TAG: Record<string, string> = { bold: 'strong', underline: 'u', strike: 's', highlight: 'mark', italic: 'em' }

/** Runs as HTML. The text is written as it is: it must already be escaped. */
export function runsToHtml(runs: Run[]): string {
  let html = ''
  let open: { key: string; value: string | true }[] = []
  const close = (to: number) => {
    while (open.length > to) {
      const o = open.pop()!
      html += o.key === 'link' ? '</a>' : `</${TAG[o.key]}>`
    }
  }
  for (const r of runs) {
    const want = ORDER.filter((k) => r.marks[k]).map((k) => ({ key: k as string, value: r.marks[k]! as string | true }))
    let common = 0
    while (common < open.length && common < want.length && open[common].key === want[common].key && open[common].value === want[common].value) common++
    close(common)
    for (const w of want.slice(common)) {
      html += w.key === 'link' ? `<a href="${w.value}" rel="noopener noreferrer">` : `<${TAG[w.key]}>`
      open.push(w)
    }
    html += r.marks.code ? `<code>${r.text}</code>` : r.text
  }
  close(0)
  return html
}
