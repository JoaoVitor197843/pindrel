// The body of a page: a flat list of blocks (no nesting yet), the shape that will sync as `notes.content`.

export interface ChecklistItem {
  id: string
  text: string
  done: boolean
}

export interface TableColumn {
  id: string
  label: string
  /** Width in px. */
  w: number
}

export type BlockType = 'paragraph' | 'heading' | 'quote' | 'callout' | 'toggle' | 'divider' | 'checklist' | 'code' | 'spoiler' | 'secure' | 'table' | 'image' | 'bullet' | 'numbered' | 'toc' | 'bookmark' | 'pagelink' | 'video' | 'audio' | 'pdf' | 'file'

/** Section titles come in three sizes; an old heading without a level is the middle one. */
export type HeadingLevel = 1 | 2 | 3
export const HEADING_LEVELS: readonly HeadingLevel[] = [1, 2, 3]
export const levelOf = (b: { level?: HeadingLevel }): HeadingLevel => b.level ?? 2

/** How a callout looks and what it says: a note, good news, a warning, a danger. */
export type CalloutTone = 'info' | 'success' | 'warning' | 'danger'
export const TONES: readonly { key: CalloutTone; label: string; icon: string }[] = [
  { key: 'info', label: 'Nota', icon: '💡' },
  { key: 'success', label: 'Sucesso', icon: '✅' },
  { key: 'warning', label: 'Atenção', icon: '⚠️' },
  { key: 'danger', label: 'Perigo', icon: '🚫' },
]
export const isTone = (t: unknown): t is CalloutTone => TONES.some((x) => x.key === t)
export const toneOf = (b: { tone?: CalloutTone }): CalloutTone => b.tone ?? 'info'

/** List items nest up to this many levels (the flat model keeps the level on the item). */
export const MAX_INDENT = 3

export type Block =
  | { id: string; type: 'paragraph'; text: string }
  /** With `toggle` the title opens and closes a plain-text `body`, like the toggle block does. */
  | { id: string; type: 'heading'; text: string; level?: HeadingLevel; toggle?: true; body?: string }
  | { id: string; type: 'quote'; text: string }
  | { id: string; type: 'callout'; text: string; tone?: CalloutTone }
  /** A title that opens and closes a body (the flat model has no children, so the body is plain text). */
  | { id: string; type: 'toggle'; text: string; body: string }
  | { id: string; type: 'divider' }
  | { id: string; type: 'checklist'; items: ChecklistItem[] }
  | { id: string; type: 'code'; lang: string; text: string }
  | { id: string; type: 'spoiler'; text: string }
  /** Hidden until the vault is unlocked; its text is never rendered while locked. */
  | { id: string; type: 'secure'; text: string }
  | { id: string; type: 'table'; cols: TableColumn[]; rows: Record<string, string>[] }
  /** Items of a bulleted or numbered list; the numbers are counted when the page is drawn, never stored. */
  | { id: string; type: 'bullet'; text: string; indent?: number }
  | { id: string; type: 'numbered'; text: string; indent?: number }
  /** The page's own section titles as links; it holds nothing, so it never goes stale. */
  | { id: string; type: 'toc' }
  /** A link shown as a card. `url` is http(s) or mailto, checked when it is set; nothing is fetched from it. */
  | { id: string; type: 'bookmark'; url: string; title: string }
  /** A card that opens another page of the workspace. `title` is the name it had the last time the page was seen (the card shows the live one). */
  | { id: string; type: 'pagelink'; pageId: string; title: string }
  /** Media that stays where it is: only the address is kept, and nothing is fetched until the person plays or opens it. */
  | { id: string; type: 'video' | 'audio' | 'pdf'; url: string; title: string; fileId?: string }
  /** A file kept on this server (sent in pieces, see api/files.ts). `level`: 1 plays or shows in the page, 2 and 3 only download. */
  | { id: string; type: 'file'; fileId: string; name: string; size: number; mime: string; level: 1 | 2 | 3 }
  /** `src` is an object URL of a file picked in this session (not persisted yet). */
  | { id: string; type: 'image'; name: string | null; src: string | null; fileId?: string }

export const LANGUAGES = ['texto', 'python', 'javascript', 'typescript', 'go', 'rust', 'sql', 'bash', 'json', 'html', 'css'] as const

export const MAX_TEXT = 20_000
export const MIN_COL_WIDTH = 80
export const MAX_COL_WIDTH = 600
export const MAX_COLS = 12
export const MAX_ROWS = 200
export const MAX_BLOCKS = 500
export const MAX_ITEMS = 100

let seq = 0
export const newId = (prefix = 'b') => `${prefix}${Date.now().toString(36)}${(seq++).toString(36)}`

export function makeBlock(type: BlockType, opts: { level?: HeadingLevel; toggle?: boolean } = {}): Block {
  const id = newId()
  switch (type) {
    case 'heading':
      return { id, type, text: '', ...(opts.level && opts.level !== 2 ? { level: opts.level } : {}), ...(opts.toggle ? { toggle: true as const, body: '' } : {}) }
    case 'bullet':
    case 'numbered':
      return { id, type, text: '', indent: 0 }
    case 'toc':
      return { id, type }
    case 'bookmark':
    case 'video':
    case 'audio':
    case 'pdf':
      return { id, type, url: '', title: '' }
    case 'pagelink':
      return { id, type, pageId: '', title: '' }
    case 'file':
      return { id, type, fileId: '', name: '', size: 0, mime: '', level: 3 }
    case 'paragraph':
    case 'quote':
    case 'callout':
    case 'spoiler':
    case 'secure':
      return { id, type, text: '' }
    case 'toggle':
      return { id, type, text: '', body: '' }
    case 'divider':
      return { id, type }
    case 'checklist':
      return { id, type, items: [{ id: newId('i'), text: '', done: false }] }
    case 'code':
      return { id, type, lang: 'texto', text: '' }
    case 'table': {
      const cols = [0, 1, 2].map((n) => ({ id: newId('c'), label: `Coluna ${n + 1}`, w: 160 }))
      return { id, type, cols, rows: [0, 1, 2].map(() => Object.fromEntries(cols.map((c) => [c.id, '']))) }
    }
    case 'image':
      return { id, type, name: null, src: null }
  }
}

/** Plain text of a block, for the card excerpt and for search. Secure blocks never contribute. */
export function blockText(b: Block): string {
  switch (b.type) {
    case 'heading':
      return b.toggle ? `${b.text} ${b.body ?? ''}`.trim() : b.text
    case 'paragraph':
    case 'quote':
    case 'callout':
    case 'code':
    case 'spoiler':
    case 'bullet':
    case 'numbered':
      return b.text
    case 'bookmark':
    case 'video':
    case 'audio':
    case 'pdf':
    case 'pagelink':
      return b.title
    case 'file':
      return b.name
    case 'toggle':
      return `${b.text} ${b.body}`.trim()
    case 'checklist':
      return b.items.map((i) => i.text).join(' ')
    case 'table':
      return b.rows.flatMap((r) => b.cols.map((c) => r[c.id] ?? '')).join(' ')
    default:
      return ''
  }
}

/** The text a page card shows under the title: the first block that has some, never a spoiler or a secret. */
export function excerptOf(blocks: Block[], max = 240): string {
  for (const b of blocks) {
    if (b.type === 'spoiler' || b.type === 'secure') continue
    const t = blockText(b).replace(/\s+/g, ' ').trim()
    if (t) return t.slice(0, max)
  }
  return ''
}

export function checklistProgress(blocks: Block[]): { done: number; total: number } {
  let done = 0
  let total = 0
  for (const b of blocks) {
    if (b.type !== 'checklist') continue
    total += b.items.length
    done += b.items.filter((i) => i.done).length
  }
  return { done, total }
}

/** A short "há 2 h" for the page header. */
export function ago(ms: number, now = Date.now()): string {
  const s = Math.max(0, Math.round((now - ms) / 1000))
  if (s < 60) return 'agora há pouco'
  const m = Math.round(s / 60)
  if (m < 60) return `há ${m} min`
  const h = Math.round(m / 60)
  if (h < 24) return `há ${h} h`
  const d = Math.round(h / 24)
  const months = Math.round(d / 30)
  return d < 30 ? `há ${d} d` : `há ${months} ${months === 1 ? 'mês' : 'meses'}`
}

/**
 * Moves `list[from]` so it lands in the gap `at` (0 = before the first item, length = after the last), the way a drop
 * indicator between two rows reads. Returns false when nothing moves.
 */
export function moveItem<T>(list: T[], from: number, at: number): boolean {
  if (!Number.isInteger(from) || !Number.isInteger(at)) return false
  if (from < 0 || from >= list.length || at < 0 || at > list.length) return false
  const to = at > from ? at - 1 : at
  if (to === from) return false
  const [item] = list.splice(from, 1)
  list.splice(to, 0, item)
  return true
}

/** Blocks that are just a piece of text, and so can be turned into one another without losing anything. */
/** Blocks that hold an address and a title: a link card, and the three kinds of media that stay on their own server. */
export type UrlBlockType = 'bookmark' | 'video' | 'audio' | 'pdf'
export const URL_TYPES: readonly UrlBlockType[] = ['bookmark', 'video', 'audio', 'pdf']
export const isUrlBlock = (b: Block): b is Extract<Block, { type: UrlBlockType }> => (URL_TYPES as readonly string[]).includes(b.type)

const MEDIA_EXT = {
  video: /\.(mp4|m4v|webm|ogv|mov)$/i,
  audio: /\.(mp3|m4a|aac|wav|ogg|oga|opus|flac)$/i,
} as const

/** Whether an address points straight at a file the browser can play (not a page that shows a player, like YouTube). */
export function isDirectMedia(kind: 'video' | 'audio', url: string): boolean {
  try {
    return MEDIA_EXT[kind].test(new URL(url).pathname)
  } catch {
    return false
  }
}

/** The block that shows a file of this type: media where the browser can show it, a file card for everything else. */
export function blockTypeForFile(mime: string, level: number): 'image' | 'video' | 'audio' | 'pdf' | 'file' {
  if (level !== 1) return 'file'
  if (mime.startsWith('image/')) return 'image'
  if (mime.startsWith('video/') || mime === 'application/ogg') return 'video'
  if (mime.startsWith('audio/')) return 'audio'
  if (mime === 'application/pdf') return 'pdf'
  return 'file'
}

/** Ids of the files kept on the server that these blocks use. */
export function fileIdsOf(blocks: readonly Block[]): string[] {
  const out = new Set<string>()
  for (const b of blocks) if ('fileId' in b && b.fileId) out.add(b.fileId)
  return [...out]
}

export const TEXT_TYPES = ['paragraph', 'heading', 'quote', 'callout', 'bullet', 'numbered'] as const
export type TextType = (typeof TEXT_TYPES)[number]
export const isTextType = (t: string): t is TextType => (TEXT_TYPES as readonly string[]).includes(t)

export const wordCount = (text: string) => text.match(/\S+/g)?.length ?? 0

export interface PageStats {
  words: number
  chars: number
  /** Reading time in minutes at 200 words a minute; 0 for an empty page, never less than 1 otherwise. */
  minutes: number
}

/** What the page says in words. Secure blocks never count: their text is not part of what the page shows. */
export function pageStats(blocks: Block[]): PageStats {
  let words = 0
  let chars = 0
  for (const b of blocks) {
    const text = blockText(b)
    words += wordCount(text)
    chars += text.length
  }
  return { words, chars, minutes: words ? Math.max(1, Math.ceil(words / 200)) : 0 }
}

export interface OutlineItem {
  id: string
  text: string
  level: HeadingLevel
}

/** The section titles of the page, in order, with their sizes. */
export function outline(blocks: Block[]): OutlineItem[] {
  return blocks.flatMap((b) => (b.type === 'heading' ? [{ id: b.id, text: b.text.replace(/\s+/g, ' ').trim() || 'Sem título', level: levelOf(b) }] : []))
}

/**
 * The number each item of a numbered list shows. Items count up at their own level; a deeper level starts again under
 * every new parent, and any block that is not part of the list ends it.
 */
export function numbering(blocks: Block[]): Map<string, number> {
  const out = new Map<string, number>()
  let counters: number[] = []
  for (const b of blocks) {
    if (b.type === 'numbered') {
      const d = Math.min(Math.max(b.indent ?? 0, 0), MAX_INDENT)
      counters = counters.slice(0, d + 1)
      while (counters.length < d) counters.push(0)
      counters[d] = (counters[d] ?? 0) + 1
      out.set(b.id, counters[d])
    } else if (b.type === 'bullet') {
      counters = counters.slice(0, Math.min(Math.max(b.indent ?? 0, 0), MAX_INDENT))
    } else counters = []
  }
  return out
}

/** Cover bands: gradients of the app's own tokens, so a cover costs no image, no upload and no memory. */
export const COVERS = [
  { key: 'musgo', label: 'Musgo', css: 'linear-gradient(120deg, color-mix(in oklab, var(--color-accent) 80%, var(--color-bg)), color-mix(in oklab, var(--color-tag-teal) 45%, var(--color-bg)))' },
  { key: 'ferrugem', label: 'Ferrugem', css: 'linear-gradient(120deg, color-mix(in oklab, var(--color-tag-rust) 60%, var(--color-bg)), color-mix(in oklab, var(--color-tag-gold) 40%, var(--color-bg)))' },
  { key: 'oceano', label: 'Oceano', css: 'linear-gradient(120deg, color-mix(in oklab, var(--color-tag-blue) 55%, var(--color-bg)), color-mix(in oklab, var(--color-tag-teal) 40%, var(--color-bg)))' },
  { key: 'ameixa', label: 'Ameixa', css: 'linear-gradient(120deg, color-mix(in oklab, var(--color-tag-plum) 60%, var(--color-bg)), color-mix(in oklab, var(--color-tag-blue) 35%, var(--color-bg)))' },
  { key: 'areia', label: 'Areia', css: 'linear-gradient(120deg, color-mix(in oklab, var(--color-tag-gold) 45%, var(--color-bg)), color-mix(in oklab, var(--color-cream) 25%, var(--color-bg)))' },
  { key: 'noite', label: 'Noite', css: 'linear-gradient(120deg, var(--color-surface), color-mix(in oklab, var(--color-line) 70%, var(--color-bg)))' },
] as const

