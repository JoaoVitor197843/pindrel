import { TONES, blockText, levelOf, numbering, outline, toneOf, type Block } from './blocks'
import { escapeHtml, inlineHtml, markdownMarks } from './inline'
import type { NotePage, Tag } from './workspace.svelte'

const MAX_IMPORT_FILES = 20
const MAX_IMPORT_BYTES = 1_000_000
const EXCERPT = 240

export interface ExportOptions {
  /** Secure blocks are left out unless the person asked for them (and may see them). */
  includeSecure?: boolean
}

export type ExportFormat = 'md' | 'html' | 'txt' | 'json'

export const FORMATS: Record<ExportFormat, { label: string; ext: string; mime: string }> = {
  md: { label: 'Markdown', ext: 'md', mime: 'text/markdown' },
  html: { label: 'HTML', ext: 'html', mime: 'text/html' },
  txt: { label: 'Texto simples', ext: 'txt', mime: 'text/plain' },
  json: { label: 'JSON', ext: 'json', mime: 'application/json' },
}

/** A page's blocks; one that was never opened has only its excerpt. */
const blocksOf = (p: NotePage): Block[] =>
  p.content ?? (p.excerpt ? [{ id: 'x', type: 'paragraph', text: p.excerpt }] : [])

const tagNames = (p: NotePage, tags: Tag[]) => p.tags.map((id) => tags.find((t) => t.id === id)?.name ?? id)

const oneLine = (s: string) => s.replace(/\s+/g, ' ').trim()

/** What a block needs to know about the others: the number of a list item, the titles a table of contents lists. */
interface Ctx {
  numbers: Map<string, number>
  titles: ReturnType<typeof outline>
}
const ctxOf = (blocks: Block[]): Ctx => ({ numbers: numbering(blocks), titles: outline(blocks) })
const isItem = (b: Block) => b.type === 'bullet' || b.type === 'numbered'

/** Blocks, one under the other: list items stay together, everything else is set apart by a blank line. */
function joinBlocks(blocks: Block[], render: (b: Block, ctx: Ctx) => string): string {
  const ctx = ctxOf(blocks)
  let out = ''
  let prev: Block | null = null
  for (const b of blocks) {
    const text = render(b, ctx)
    if (!text) continue
    out += prev ? (isItem(prev) && isItem(b) ? '\n' : '\n\n') : ''
    out += text
    prev = b
  }
  return out
}

const ALERT = { info: 'NOTE', success: 'TIP', warning: 'WARNING', danger: 'CAUTION' } as const

/** A code fence longer than any run of backticks inside the code, so the code can never close it early. */
function fence(text: string): string {
  const longest = Math.max(0, ...[...text.matchAll(/`+/g)].map((m) => m[0].length))
  return '`'.repeat(Math.max(3, longest + 1))
}

const cell = (s: string) => oneLine(s).replace(/\|/g, '\\|')

function mdBlock(b: Block, opt: ExportOptions, ctx: Ctx): string {
  switch (b.type) {
    case 'heading':
      return b.toggle
        ? `<details><summary><h${levelOf(b)}>${escapeHtml(oneLine(b.text))}</h${levelOf(b)}></summary>\n\n${markdownMarks(b.body ?? '')}\n\n</details>`
        : `${'#'.repeat(levelOf(b))} ${markdownMarks(oneLine(b.text))}`
    case 'paragraph':
      return markdownMarks(b.text)
    case 'quote':
      return markdownMarks(b.text).split('\n').map((l) => `> ${l}`.trimEnd()).join('\n')
    case 'callout':
      return `> [!${ALERT[toneOf(b)]}]\n${markdownMarks(b.text).split('\n').map((l) => `> ${l}`.trimEnd()).join('\n')}`
    case 'toggle':
      return `<details><summary>${escapeHtml(oneLine(b.text))}</summary>\n\n${markdownMarks(b.body)}\n\n</details>`
    case 'divider':
      return '---'
    case 'checklist':
      return b.items.map((i) => `- [${i.done ? 'x' : ' '}] ${oneLine(i.text)}`).join('\n')
    case 'code': {
      const f = fence(b.text)
      return `${f}${b.lang === 'texto' ? '' : b.lang}\n${b.text}\n${f}`
    }
    case 'spoiler':
      return `<details><summary>spoiler</summary>\n\n${b.text}\n\n</details>`
    case 'secure':
      return opt.includeSecure ? b.text : '> [bloco seguro omitido]'
    case 'table': {
      const head = `| ${b.cols.map((c) => cell(c.label)).join(' | ')} |`
      const rule = `| ${b.cols.map(() => '---').join(' | ')} |`
      const rows = b.rows.map((r) => `| ${b.cols.map((c) => cell(r[c.id] ?? '')).join(' | ')} |`)
      return [head, rule, ...rows].join('\n')
    }
    case 'image':
      return b.name ? `![${oneLine(b.name)}](${encodeURI(b.name)})` : ''
    case 'bullet':
      return `${'  '.repeat(b.indent ?? 0)}- ${markdownMarks(oneLine(b.text))}`
    case 'numbered':
      return `${'   '.repeat(b.indent ?? 0)}${ctx.numbers.get(b.id) ?? 1}. ${markdownMarks(oneLine(b.text))}`
    case 'toc':
      return ctx.titles.map((t) => `${'  '.repeat(t.level - 1)}- ${oneLine(t.text)}`).join('\n')
    case 'bookmark':
    case 'video':
    case 'audio':
    case 'pdf':
      if (!b.url && 'fileId' in b && b.fileId) return `📎 ${oneLine(b.title) || 'arquivo'}`
      return b.url ? `[${oneLine(b.title) || b.url}](${b.url})` : ''
    case 'pagelink':
      return b.pageId && b.title ? `[${oneLine(b.title)}](/notes/${b.pageId})` : ''
    case 'file':
      // a file kept on the server has no public address: the name is all that goes out
      return b.fileId ? `📎 ${oneLine(b.name) || 'arquivo'}` : ''
  }
}

export function pageToMarkdown(p: NotePage, tags: Tag[], opt: ExportOptions = {}): string {
  const names = tagNames(p, tags)
  const body = joinBlocks(blocksOf(p), (b, ctx) => mdBlock(b, opt, ctx))
  return `# ${oneLine(p.title) || 'Sem título'}\n\n${names.length ? `tags: ${names.join(', ')}\n\n` : ''}${body}${body ? '\n' : ''}`
}

function txtBlock(b: Block, opt: ExportOptions, ctx: Ctx): string {
  switch (b.type) {
    case 'heading':
      return b.toggle ? [b.text.toUpperCase(), b.body].filter(Boolean).join('\n') : b.text.toUpperCase()
    case 'quote':
      return b.text.split('\n').map((l) => `> ${l}`.trimEnd()).join('\n')
    case 'callout':
      return `${TONES.find((t) => t.key === toneOf(b))!.label}: ${b.text}`
    case 'toggle':
      return [b.text, b.body].filter(Boolean).join('\n')
    case 'divider':
      return '----------'
    case 'checklist':
      return b.items.map((i) => `[${i.done ? 'x' : ' '}] ${oneLine(i.text)}`).join('\n')
    case 'secure':
      return opt.includeSecure ? b.text : '[bloco seguro omitido]'
    case 'table':
      return [b.cols.map((c) => oneLine(c.label)).join('\t'), ...b.rows.map((r) => b.cols.map((c) => oneLine(r[c.id] ?? '')).join('\t'))].join('\n')
    case 'image':
      return b.name ? `[imagem: ${oneLine(b.name)}]` : ''
    case 'bullet':
      return `${'  '.repeat(b.indent ?? 0)}• ${oneLine(b.text)}`
    case 'numbered':
      return `${'   '.repeat(b.indent ?? 0)}${ctx.numbers.get(b.id) ?? 1}. ${oneLine(b.text)}`
    case 'toc':
      return ctx.titles.map((t) => `${'  '.repeat(t.level - 1)}${oneLine(t.text)}`).join('\n')
    case 'bookmark':
    case 'video':
    case 'audio':
    case 'pdf':
      if (!b.url && 'fileId' in b && b.fileId) return `[arquivo: ${oneLine(b.title) || 'sem nome'}]`
      return b.url ? `${oneLine(b.title) || b.url} (${b.url})` : ''
    case 'pagelink':
      return b.title ? `→ ${oneLine(b.title)}` : ''
    case 'file':
      return b.fileId ? `[arquivo: ${oneLine(b.name) || 'sem nome'}]` : ''
    default:
      return blockText(b)
  }
}

export function pageToText(p: NotePage, tags: Tag[], opt: ExportOptions = {}): string {
  const names = tagNames(p, tags)
  const body = joinBlocks(blocksOf(p), (b, ctx) => txtBlock(b, opt, ctx))
  return `${oneLine(p.title) || 'Sem título'}\n${names.length ? `tags: ${names.join(', ')}\n` : ''}\n${body}${body ? '\n' : ''}`
}

export { escapeHtml }

const rich = (t: string) => inlineHtml(escapeHtml(t)).replace(/\n/g, '<br>')
const para = (t: string) => `<p>${rich(t)}</p>`

function htmlBlock(b: Block, opt: ExportOptions, ctx: Ctx): string {
  switch (b.type) {
    case 'heading':
      return b.toggle
        ? `<details><summary><h${levelOf(b)}>${inlineHtml(escapeHtml(oneLine(b.text)))}</h${levelOf(b)}></summary>${para(b.body ?? '')}</details>`
        : `<h${levelOf(b)}>${inlineHtml(escapeHtml(oneLine(b.text)))}</h${levelOf(b)}>`
    case 'paragraph':
      return para(b.text)
    case 'quote':
      return `<blockquote>${rich(b.text)}</blockquote>`
    case 'callout':
      return `<aside class="callout ${toneOf(b)}">${rich(b.text)}</aside>`
    case 'toggle':
      return `<details><summary>${inlineHtml(escapeHtml(oneLine(b.text)))}</summary>${para(b.body)}</details>`
    case 'divider':
      return '<hr>'
    case 'checklist':
      return `<ul class="check">${b.items.map((i) => `<li>${i.done ? '☑' : '☐'} ${escapeHtml(oneLine(i.text))}</li>`).join('')}</ul>`
    case 'code':
      return `<pre><code>${escapeHtml(b.text)}</code></pre>`
    case 'spoiler':
      return `<details><summary>spoiler</summary>${para(b.text)}</details>`
    case 'secure':
      return opt.includeSecure ? para(b.text) : '<p><em>[bloco seguro omitido]</em></p>'
    case 'table':
      return `<table><thead><tr>${b.cols.map((c) => `<th>${escapeHtml(oneLine(c.label))}</th>`).join('')}</tr></thead><tbody>${b.rows
        .map((r) => `<tr>${b.cols.map((c) => `<td>${escapeHtml(oneLine(r[c.id] ?? ''))}</td>`).join('')}</tr>`)
        .join('')}</tbody></table>`
    case 'image':
      return b.name ? `<p><em>[imagem: ${escapeHtml(oneLine(b.name))}]</em></p>` : ''
    case 'bullet':
      return `<ul><li style="margin-left:${(b.indent ?? 0) * 1.5}em">${inlineHtml(escapeHtml(oneLine(b.text)))}</li></ul>`
    case 'numbered':
      return `<ol><li value="${ctx.numbers.get(b.id) ?? 1}" style="margin-left:${(b.indent ?? 0) * 1.5}em">${inlineHtml(escapeHtml(oneLine(b.text)))}</li></ol>`
    case 'toc':
      return `<nav><ul>${ctx.titles.map((t) => `<li style="margin-left:${(t.level - 1) * 1.5}em">${escapeHtml(oneLine(t.text))}</li>`).join('')}</ul></nav>`
    case 'bookmark':
    case 'pdf':
      if (!b.url && 'fileId' in b && b.fileId) return `<p><em>[arquivo: ${escapeHtml(oneLine(b.title) || 'sem nome')}]</em></p>`
      return b.url ? `<p><a href="${escapeHtml(b.url)}" rel="noopener noreferrer">${escapeHtml(oneLine(b.title) || b.url)}</a></p>` : ''
    case 'video':
    case 'audio': {
      if (!b.url && b.fileId) return `<p><em>[arquivo: ${escapeHtml(oneLine(b.title) || 'sem nome')}]</em></p>`
      if (!b.url) return ''
      const tag = b.type === 'video' ? 'video' : 'audio'
      const caption = oneLine(b.title) ? `<p>${escapeHtml(oneLine(b.title))}</p>` : ''
      return `<${tag} controls preload="none" src="${escapeHtml(b.url)}"></${tag}>${caption}`
    }
    case 'pagelink':
      return b.pageId && b.title ? `<p><a href="/notes/${escapeHtml(b.pageId)}">${escapeHtml(oneLine(b.title))}</a></p>` : ''
    case 'file':
      return b.fileId ? `<p><em>[arquivo: ${escapeHtml(oneLine(b.name) || 'sem nome')}]</em></p>` : ''
  }
}

export function pageToHtml(p: NotePage, tags: Tag[], opt: ExportOptions = {}): string {
  const names = tagNames(p, tags)
  const title = escapeHtml(oneLine(p.title) || 'Sem título')
  const body = joinBlocks(blocksOf(p), (b, ctx) => htmlBlock(b, opt, ctx)).replace(/<\/(ul|ol)>\n<\1>/g, '\n')
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{max-width:42rem;margin:2rem auto;padding:0 1rem;font:17px/1.6 system-ui,sans-serif;color:#1c1a17}h1,h2{font-family:serif}pre{background:#f1eee6;padding:1rem;overflow:auto}table{border-collapse:collapse}td,th{border:1px solid #d6cfbe;padding:.3rem .6rem;text-align:left}.check{list-style:none;padding:0}.tags{color:#6e6858;font:14px monospace}</style>
</head>
<body>
<h1>${title}</h1>
${names.length ? `<p class="tags">${names.map((n) => `#${escapeHtml(n)}`).join(' ')}</p>\n` : ''}${body}
</body>
</html>
`
}

export function pageToJson(p: NotePage, tags: Tag[], opt: ExportOptions = {}): string {
  const blocks = blocksOf(p).map((b) => (b.type === 'secure' && !opt.includeSecure ? { id: b.id, type: 'secure', omitted: true } : b))
  return JSON.stringify(
    { app: 'pindrel', title: p.title, tags: tagNames(p, tags), created: new Date(p.created).toISOString(), updated: new Date(p.updated).toISOString(), blocks },
    null,
    2,
  )
}

export function exportPage(p: NotePage, tags: Tag[], format: ExportFormat, opt: ExportOptions = {}): string {
  switch (format) {
    case 'md':
      return pageToMarkdown(p, tags, opt)
    case 'html':
      return pageToHtml(p, tags, opt)
    case 'txt':
      return pageToText(p, tags, opt)
    case 'json':
      return pageToJson(p, tags, opt)
  }
}

/** A safe file name for a page: no slashes, no dots at the start, no control characters, never empty. */
export function fileNameFor(title: string, ext: string): string {
  const base = oneLine(title)
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .replace(/[^A-Za-z0-9._-]+/g, '-')
    .replace(/^[-.]+|[-.]+$/g, '')
    .slice(0, 60)
  return `${base || 'pagina'}.${ext}`
}

/** Pages that can leave the app in clear: the vault, and the trash, never do. */
const exportable = (pages: NotePage[]) => pages.filter((p) => !p.trashed && !p.locked)

export function toJson(pages: NotePage[], tags: Tag[]): string {
  const rows = exportable(pages).map((p) => ({
    title: p.title,
    excerpt: p.excerpt,
    tags: tagNames(p, tags),
    updated: new Date(p.updated).toISOString(),
    blocks: p.content ? p.content.length : p.blocks,
    sharedBy: p.sharedBy,
    content: p.content ? (JSON.parse(pageToJson(p, tags)).blocks as unknown[]) : null,
  }))
  return JSON.stringify({ app: 'pindrel', pages: rows }, null, 2)
}

export function toMarkdown(pages: NotePage[], tags: Tag[]): string {
  return exportable(pages)
    .map((p) => pageToMarkdown(p, tags))
    .join('\n---\n\n')
}

export interface Imported {
  title: string
  excerpt: string
}

/** A text/markdown file becomes a page: the first heading (or the file name) is the title, the text the excerpt. */
export function parseImported(fileName: string, text: string): Imported {
  const lines = text.replace(/\r\n?/g, '\n').split('\n')
  const heading = lines.find((l) => /^#{1,6}\s+\S/.test(l))
  const fallback = fileName.replace(/\.[^.]+$/, '').trim() || 'Sem título'
  const title = (heading ? heading.replace(/^#{1,6}\s+/, '').trim() : fallback).slice(0, 120)
  const body = lines
    .filter((l) => l !== heading)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim()
  return { title, excerpt: body.slice(0, EXCERPT) }
}

export interface ImportResult {
  pages: Imported[]
  skipped: number
}

/** Reads what the person picked; anything that is not a small .md/.txt file is counted as skipped, never read. */
export async function readImports(files: File[]): Promise<ImportResult> {
  const pages: Imported[] = []
  let skipped = Math.max(0, files.length - MAX_IMPORT_FILES)
  for (const file of files.slice(0, MAX_IMPORT_FILES)) {
    if (!/\.(md|txt)$/i.test(file.name) || file.size > MAX_IMPORT_BYTES) {
      skipped++
      continue
    }
    try {
      pages.push(parseImported(file.name, await file.text()))
    } catch {
      skipped++
    }
  }
  return { pages, skipped }
}

export function download(name: string, content: string, mime: string): boolean {
  try {
    const url = URL.createObjectURL(new Blob([content], { type: mime }))
    const a = document.createElement('a')
    a.href = url
    a.download = name
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
    return true
  } catch {
    return false
  }
}
