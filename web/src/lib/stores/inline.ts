// Inline formatting kept as plain markdown markers inside the text, so it survives every export and costs nothing
// at rest: the editor edits text, and these functions only add or take away the markers.

export type Mark = 'bold' | 'italic' | 'underline' | 'code'

// markdown has no underline: `++text++` is the usual extension, and it becomes <u> wherever the text is shown or exported
// `++x++` between words; a plus sign next to a letter (C++, i++) is never a mark, nor is one around spaces
const UNDERLINE = /(^|[^\w+])\+\+(?=\S)([^+\n]*?[^\s+])\+\+(?![\w+])/g

export const MARKERS: Record<Mark, string> = { bold: '**', italic: '_', underline: '++', code: '`' }

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
  if (text.slice(from - m.length, from) === m && text.slice(to, to + m.length) === m && from >= m.length) {
    const next = text.slice(0, from - m.length) + sel + text.slice(to + m.length)
    return { text: next, start: from - m.length, end: to - m.length }
  }
  if (sel.length > 2 * m.length && sel.startsWith(m) && sel.endsWith(m)) {
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

/** Markers in text that is already HTML-escaped become tags. Only the three marks and safe links are recognised. */
export function inlineHtml(escaped: string): string {
  return escaped
    .split(/(`[^`\n]+`)/)
    .map((part, i) => {
      if (i % 2 === 1) return `<code>${part.slice(1, -1)}</code>`
      return part
        .replace(/\[([^\]\n]+)\]\(((?:https?:\/\/|mailto:)[^\s)]+)\)/g, '<a href="$2" rel="noopener noreferrer">$1</a>')
        .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
        .replace(UNDERLINE, '$1<u>$2</u>')
        .replace(/(^|[^\w])_([^_\n]+)_(?!\w)/g, '$1<em>$2</em>')
    })
    .join('')
}

/** Every character that could start markup, so text can never inject anything where it is shown or exported. */
export const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!)

/** The text drawn with its marks (for a block that is not being edited), or null when it has none: no work, no node. */
export function renderMarks(text: string): string | null {
  // cheap exit for the common case before any regex work
  if (!/[*_`[+]/.test(text)) return null
  const plain = escapeHtml(text)
  const html = inlineHtml(plain)
  return html === plain ? null : html.replace(/<a href=/g, '<a target="_blank" href=')
}

/** Markdown for text with marks: everything is kept as typed, except `++underline++`, which markdown lacks (it becomes <u>). */
export function markdownMarks(text: string): string {
  return text
    .split(/(`[^`\n]+`)/)
    .map((part, i) => (i % 2 === 1 ? part : part.replace(UNDERLINE, '$1<u>$2</u>')))
    .join('')
}
