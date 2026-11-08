import { parseInline, runsToHtml } from './inlineParse'

// Inline formatting kept as plain markdown markers inside the text, so it survives every export and costs nothing
// at rest: the editor edits text, and these functions only add or take away the markers.

export type Mark = 'bold' | 'italic' | 'underline' | 'strike' | 'highlight' | 'code'

// The markers are the ones most apps use: **bold**, *italic*, __underline__, ~~strike~~, `code`. Markdown has no
// underline, so `__x__` becomes <u> wherever the text is shown or exported. `_x_` is still read as italic (it is
// standard markdown) but the editor writes `*x*`.
// A marker only counts hugging text: `2 * 3 * 4`, `snake_case_name`, `a ~~ b` and `~~ a ~~` are plain text.
// `__x__` is read by the shared reader; this one only serves the markdown export, where it must become <u>
const HIGHLIGHT = /(^|[^\w=])==(?=[^\s=])([^=\n]*?[^\s=])==(?![\w=])/g
const UNDERLINE = /(^|[^\w_])__(?=[^\s_])([^_\n]*?[^\s_])__(?![\w_])/g

export const MARKERS: Record<Mark, string> = { bold: '**', italic: '*', underline: '__', strike: '~~', highlight: '==', code: '`' }

export interface TextEdit {
  text: string
  /** The selection to restore after the edit. */
  start: number
  end: number
}

/** Wraps the selection in the marker, or takes it off when it is already there. An empty selection changes nothing. */
export function toggleMark(text: string, start: number, end: number, mark: Mark): TextEdit | null {
  const m = MARKERS[mark]
  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end > text.length) return null
  let from = Math.min(start, end)
  let to = Math.max(start, end)
  // markers go against the words, never against the spaces around them
  while (from < to && /\s/.test(text[from])) from++
  while (to > from && /\s/.test(text[to - 1])) to--
  if (from === to) return null

  const sel = text.slice(from, to)
  // `*` is shared by bold (`**`) and italic (`*`): it is italic only when the run of stars is odd (`***x***` is both)
  const run = (i: number, step: 1 | -1) => {
    let n = 0
    while (text[i + (step === 1 ? n : -n - 1)] === '*') n++
    return n
  }
  const selRun = (str: string, fromEnd: boolean) => {
    let n = 0
    while (n < str.length && str[fromEnd ? str.length - 1 - n : n] === '*') n++
    return n
  }
  const around =
    mark === 'italic'
      ? Math.min(run(from, -1), run(to, 1)) % 2 === 1
      : from >= m.length && text.slice(from - m.length, from) === m && text.slice(to, to + m.length) === m
  if (around) {
    const next = text.slice(0, from - m.length) + sel + text.slice(to + m.length)
    return { text: next, start: from - m.length, end: to - m.length }
  }
  const inside =
    mark === 'italic'
      ? Math.min(selRun(sel, false), selRun(sel, true)) % 2 === 1 && sel.length > 2
      : sel.length > 2 * m.length && sel.startsWith(m) && sel.endsWith(m)
  if (inside) {
    const inner = sel.slice(m.length, sel.length - m.length)
    return { text: text.slice(0, from) + inner + text.slice(to), start: from, end: from + inner.length }
  }
  return { text: `${text.slice(0, from)}${m}${sel}${m}${text.slice(to)}`, start: from + m.length, end: to + m.length }
}

/** An address a link may point at: http(s) or mailto only (never javascript: and the like). Bare domains get https. */
export function safeUrl(raw: string): string | null {
  const url = raw.trim()
  if (!url || url.length > 2000 || /[\s<>"'`]/.test(url)) return null
  const candidate = /^[a-z][a-z0-9+.-]*:/i.test(url) ? url : /^[^@/]+\.[a-z]{2,}(\/|$|\?|#)/i.test(url) ? `https://${url}` : /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(url) ? `mailto:${url}` : null
  if (!candidate) return null
  try {
    const u = new URL(candidate)
    if (u.protocol !== 'http:' && u.protocol !== 'https:' && u.protocol !== 'mailto:') return null
    // parentheses would end the markdown link early
    return candidate.replace(/\(/g, '%28').replace(/\)/g, '%29')
  } catch {
    return null
  }
}

/** Turns the selection into `[selection](url)`. Null when the selection is empty or the address is not usable. */
export function makeLink(text: string, start: number, end: number, url: string): TextEdit | null {
  const safe = safeUrl(url)
  const from = Math.min(start, end)
  const to = Math.max(start, end)
  if (!safe || from === to || from < 0 || to > text.length) return null
  const sel = text.slice(from, to).replace(/[[\]]/g, '')
  if (!sel.trim()) return null
  const link = `[${sel}](${safe})`
  return { text: text.slice(0, from) + link + text.slice(to), start: from + 1, end: from + 1 + sel.length }
}

/** Markers in text that is already HTML-escaped become tags. Only the marks and safe links are recognised. */
export function inlineHtml(escaped: string): string {
  return runsToHtml(parseInline(escaped))
}

/** Every character that could start markup, so text can never inject anything where it is shown or exported. */
export const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!)

/** The text drawn with its marks (for a block that is not being edited), or null when it has none: no work, no node. */
export function renderMarks(text: string): string | null {
  // cheap exit for the common case before any regex work
  if (!/[*_`[~=]/.test(text)) return null
  const plain = escapeHtml(text)
  const html = inlineHtml(plain)
  return html === plain ? null : html.replace(/<a href=/g, '<a target="_blank" href=')
}

/** Markdown for text with marks: everything is kept as typed, except `__underline__` (markdown reads it as bold), which becomes <u> (and `==highlight==`, which becomes <mark>). */
export function markdownMarks(text: string): string {
  return text
    .split(/(`[^`\n]+`)/)
    .map((part, i) => (i % 2 === 1 ? part : part.replace(UNDERLINE, '$1<u>$2</u>').replace(HIGHLIGHT, '$1<mark>$2</mark>')))
    .join('')
}
