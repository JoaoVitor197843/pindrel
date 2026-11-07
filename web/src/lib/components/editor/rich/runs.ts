// What every rich-text engine shares. The stored text keeps its markers (`**bold**`, `*italic*`...), so the data
// model, the export and the search do not depend on the engine: the engine gets runs of text with marks when a block
// is focused, and hands runs back that become markers again.
import { mergeRuns, parseInline, type MarkKey, type Marks, type Run } from '../../../stores/inlineParse'

export { mergeRuns, type MarkKey, type Marks, type Run }

/** The text with its markers as runs, nesting included. Uses the very same reader that draws the block at rest. */
export const parseRuns = (text: string): Run[] => parseInline(text)

// outermost first, so neighbours that share a mark stay inside one pair of markers
const ORDER = ['link', 'bold', 'underline', 'strike', 'highlight', 'italic'] as const
const OPEN: Record<string, string> = { bold: '**', underline: '__', strike: '~~', highlight: '==', italic: '*' }

const hasMarks = (m: Marks) => !!(m.bold || m.italic || m.underline || m.strike || m.highlight || m.link)
const PLAIN_KEYS = ['bold', 'italic', 'underline', 'strike', 'highlight'] as const

/** The marks two neighbours share. */
function shared(a: Marks | undefined, b: Marks): Marks {
  const out: Marks = {}
  if (!a) return out
  for (const k of PLAIN_KEYS) if (a[k] && b[k]) out[k] = true
  if (a.link && a.link === b.link) out.link = a.link
  return out
}

/**
 * Markers must hug the words and stay inside one line, so spaces and line breaks at the edge of a marked stretch move
 * out of it. A space between two runs that share the mark stays inside (`**a *b* c**` is one bold stretch).
 */
function hugging(runs: Run[]): Run[] {
  const out: Run[] = []
  runs.forEach((r, idx) => {
    if (!hasMarks(r.marks) || r.marks.code) return void out.push(r)
    const prev = runs[idx - 1]?.marks
    const next = runs[idx + 1]?.marks
    const parts = r.text.split(/(\n)/)
    parts.forEach((part, k) => {
      if (part === '\n') return void out.push({ text: part, marks: {} })
      if (!part) return
      const lead = k === 0 ? shared(prev, r.marks) : {}
      const trail = k === parts.length - 1 ? shared(next, r.marks) : {}
      const core = part.trim()
      if (!core) {
        // only spaces: marked when both sides keep the mark going
        const both: Marks = {}
        for (const key of PLAIN_KEYS) if (lead[key] && trail[key]) both[key] = true
        if (lead.link && lead.link === trail.link) both.link = lead.link
        return void out.push({ text: part, marks: both })
      }
      const at = part.indexOf(core)
      if (at) out.push({ text: part.slice(0, at), marks: lead })
      out.push({ text: core, marks: r.marks })
      if (at + core.length < part.length) out.push({ text: part.slice(at + core.length), marks: trail })
    })
  })
  return out
}

/** Runs back to the text with markers. */
export function serializeRuns(runs: Run[]): string {
  let out = ''
  let open: { key: string; value: string | true }[] = []
  const close = (to: number) => {
    while (open.length > to) {
      const o = open.pop()!
      out += o.key === 'link' ? `](${o.value})` : OPEN[o.key]
    }
  }
  for (const r of mergeRuns(hugging(mergeRuns(runs)))) {
    const want = ORDER.filter((k) => r.marks[k]).map((k) => ({ key: k as string, value: r.marks[k]! as string | true }))
    let common = 0
    while (common < open.length && common < want.length && open[common].key === want[common].key && open[common].value === want[common].value) common++
    close(common)
    for (const w of want.slice(common)) {
      out += w.key === 'link' ? '[' : OPEN[w.key]
      open.push(w)
    }
    out += r.marks.code ? `\`${r.text}\`` : r.text
  }
  close(0)
  return out
}

export const plainText = (runs: Run[]) => runs.map((r) => r.text).join('')

/** A mark that the person just finished typing with its symbols, e.g. `**word**` around the caret. */
export interface AutoMark {
  /** Offsets in the plain text (no markers) of the typed symbols and everything between them. */
  from: number
  to: number
  inner: string
  mark: MarkKey
}

// [symbol, mark, characters that can not be inside]
const SYMBOLS: { sym: string; mark: MarkKey; bar: string }[] = [
  { sym: '**', mark: 'bold', bar: '*' },
  { sym: '~~', mark: 'strike', bar: '~' },
  { sym: '==', mark: 'highlight', bar: '=' },
  { sym: '__', mark: 'underline', bar: '_' },
  { sym: '`', mark: 'code', bar: '`' },
  { sym: '*', mark: 'italic', bar: '*' },
  { sym: '_', mark: 'italic', bar: '_' },
]

const word = /[\p{L}\p{N}]/u
const inner = (bar: string) => new RegExp(`[^\\s${bar}](?:[^${bar}\\n]*[^\\s${bar}])?`, 'y')

/**
 * Looks around the caret: did the last typed symbol complete a pair? Either the closing one, typed after the words
 * (`**word|`), or the opening one, typed before words that already have a closing one (`|word**`). Null when not.
 */
export function autoMark(before: string, after = ''): AutoMark | null {
  // a long paragraph is not scanned whole: a mark that is still open is never that far from the caret
  const head = before.length > 400 ? before.slice(-400) : before
  const shift = before.length - head.length
  const tail = after.length > 400 ? after.slice(0, 400) : after
  for (const { sym, mark, bar } of SYMBOLS) {
    const pre = (at: number) => {
      const p = at > 0 ? head[at - 1] : ''
      return !(p && (word.test(p) || p === bar)) && !(p && sym.length === 2 && p === sym[0])
    }
    // the closing symbol was just typed
    if (head.endsWith(sym)) {
      const body = head.slice(0, head.length - sym.length)
      for (let open = body.length - 1; open >= 0; open--) {
        if (body.slice(open - sym.length + 1, open + 1) !== sym) continue
        const start = open - sym.length + 1
        const text = body.slice(start + sym.length)
        const re = inner(bar)
        if (pre(start) && re.test(text) && re.lastIndex === text.length && !(after && after[0] === bar)) {
          const from = shift + start
          return { from, to: shift + head.length, inner: text, mark }
        }
        break
      }
    }
    // the opening symbol was just typed
    if (head.endsWith(sym) && pre(head.length - sym.length)) {
      const re = inner(bar)
      re.lastIndex = 0
      const m = re.exec(tail)
      if (m && tail.startsWith(sym, m[0].length) && tail[m[0].length + sym.length] !== bar && !/\s/.test(tail[0] ?? ' ')) {
        const from = shift + head.length - sym.length
        return { from, to: shift + head.length + m[0].length + sym.length, inner: m[0], mark }
      }
    }
  }
  return null
}

/** The part of the runs between two plain-text offsets. */
export function sliceRuns(runs: Run[], from: number, to: number): Run[] {
  const out: Run[] = []
  let at = 0
  for (const r of runs) {
    const a = Math.max(from - at, 0)
    const b = Math.min(to - at, r.text.length)
    if (b > a) out.push({ text: r.text.slice(a, b), marks: { ...r.marks } })
    at += r.text.length
  }
  return out
}
