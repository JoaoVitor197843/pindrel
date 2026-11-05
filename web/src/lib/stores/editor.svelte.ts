import {
  checklistProgress,
  outline,
  pageStats,
  makeBlock,
  moveItem,
  newId,
  MAX_BLOCKS,
  MAX_COL_WIDTH,
  MAX_COLS,
  MAX_ITEMS,
  MAX_ROWS,
  MAX_TEXT,
  MIN_COL_WIDTH,
  isTextType,
  type Block,
  type BlockType,
} from './blocks'
import { isCover } from './cover'
import { isEmoji } from './emoji'
import type { PermKey } from './permissions'
import { MAX_TAG_NAME, type NotePage, type TagColor, type Workspace } from './workspace.svelte'

const SAVE_DELAY_MS = 600
const MAX_TITLE = 120

type Of<T extends Block['type']> = Extract<Block, { type: T }>

/** Edits one page: every change goes straight into the workspace, and the "saved" indicator follows. */
export class PageEditor {
  readonly ws: Workspace
  readonly id: string
  save = $state<'saved' | 'saving'>('saved')
  /** Spoilers and secure blocks that are open right now (not stored: they close with the page). */
  revealed = $state<Record<string, boolean>>({})
  #timer: ReturnType<typeof setTimeout> | undefined

  constructor(ws: Workspace, id: string) {
    this.ws = ws
    this.id = id
    ws.contentOf(id)
  }

  // getters, not $derived: field initializers would run before the constructor sets `ws` and `id`
  get page(): NotePage | undefined {
    return this.ws.page(this.id)
  }
  get blocks(): Block[] {
    return this.page?.content ?? []
  }
  get progress() {
    return checklistProgress(this.blocks)
  }
  get outline() {
    return outline(this.blocks)
  }

  get stats() {
    return pageStats(this.blocks)
  }

  /** Pages with tags in common, for the side panel. */
  get related() {
    return this.ws.related(this.id)
  }

  togglePin() {
    if (this.page && !this.page.trashed) this.ws.togglePin(this.id)
  }

  /** Copying a page shows everything in it, so it takes the same permission as exporting. */
  duplicate(): { id: string; images: number } | null {
    if (!this.can('export') || this.readOnly) return null
    const made = this.ws.duplicate(this.id)
    return made ? { id: made.page.id, images: made.images } : null
  }

  /** The page is in the trash: it can only be read (and restored or deleted for good). */
  get readOnly() {
    return !!this.page?.trashed
  }

  /** My page, as opposed to one somebody shared with me. */
  get isOwner() {
    return !!this.page && !this.page.sharedBy
  }

  /**
   * What I may do here. The owner may do everything; somebody the page was shared with, what the owner allowed. A page
   * in the trash lets nobody change it, whoever they are.
   */
  can(perm: PermKey): boolean {
    const p = this.page
    if (!p) return false
    if (p.sharedBy && !p.myPerms.includes(perm)) return false
    return !p.trashed || perm === 'export' || perm === 'delete'
  }

  destroy() {
    clearTimeout(this.#timer)
  }

  #changed() {
    this.ws.touch(this.id)
    this.save = 'saving'
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => (this.save = 'saved'), SAVE_DELAY_MS)
  }

  #block<T extends Block['type']>(id: string, type: T): Of<T> | undefined {
    const b = this.blocks.find((x) => x.id === id)
    return b && b.type === type ? (b as Of<T>) : undefined
  }

  #index(id: string) {
    return this.blocks.findIndex((b) => b.id === id)
  }

  setTitle(title: string) {
    const p = this.page
    if (!p || !this.can('text')) return
    p.title = title.replace(/\s+/g, ' ').slice(0, MAX_TITLE)
    this.#changed()
  }

  /** Inserts a new block after `afterId` (or at the end when null). Returns it, or null at the block limit. */
  insert(type: BlockType, afterId: string | null = null): Block | null {
    const p = this.page
    if (!p?.content || !this.can('blocks') || p.content.length >= MAX_BLOCKS) return null
    if (type === 'image' && !this.can('images')) return null
    const block = makeBlock(type)
    const found = afterId === null ? -1 : this.#index(afterId)
    const at = found < 0 ? p.content.length : found + 1
    p.content.splice(at, 0, block)
    this.#changed()
    // the reactive copy, not `block`: writing to the raw object would never reach the screen
    return p.content[at]
  }

  remove(id: string) {
    const p = this.page
    const i = this.#index(id)
    if (!p?.content || i < 0 || !this.can('blocks')) return
    p.content.splice(i, 1)
    this.#changed()
  }

  move(from: number, at: number) {
    const p = this.page
    if (!p?.content || !this.can('blocks')) return
    if (moveItem(p.content, from, at)) this.#changed()
  }

  /** Keyboard / menu move: one place up (-1) or down (+1). */
  moveBy(id: string, delta: -1 | 1) {
    const i = this.#index(id)
    if (i < 0) return
    const target = i + delta
    if (target < 0 || target >= this.blocks.length) return
    this.move(i, delta > 0 ? i + 2 : i - 1)
  }

  setText(id: string, text: string) {
    if (!this.can('text')) return
    const b = this.blocks.find((x) => x.id === id)
    if (!b || !('text' in b)) return
    b.text = text.slice(0, MAX_TEXT)
    this.#changed()
  }

  /** Enter in the middle of a text block: what follows the caret becomes a new paragraph right after it. */
  split(id: string, caret: number): Block | null {
    const b = this.blocks.find((x) => x.id === id)
    if (!b || !['paragraph', 'heading', 'quote', 'callout', 'toggle', 'spoiler'].includes(b.type) || !('text' in b) || !this.can('text')) return null
    const at = Math.min(Math.max(0, caret), b.text.length)
    const tail = b.text.slice(at)
    const made = this.insert('paragraph', id)
    if (!made || made.type !== 'paragraph') return null
    b.text = b.text.slice(0, at)
    made.text = tail
    this.#changed()
    return made
  }

  setBody(id: string, body: string) {
    const b = this.#block(id, 'toggle')
    if (b && this.can('text')) {
      b.body = body.slice(0, MAX_TEXT)
      this.#changed()
    }
  }

  /** A copy of a block right after it. Images stay single (their file belongs to the original). */
  duplicateBlock(id: string): Block | null {
    const p = this.page
    const i = this.#index(id)
    if (!p?.content || i < 0 || !this.can('blocks') || p.content.length >= MAX_BLOCKS) return null
    const src = p.content[i]
    if (src.type === 'image') return null
    const copy: Block = JSON.parse(JSON.stringify(src))
    copy.id = newId()
    if (copy.type === 'checklist') copy.items.forEach((item) => (item.id = newId('i')))
    p.content.splice(i + 1, 0, copy)
    this.#changed()
    return p.content[i + 1]
  }

  /** Changes a text block into another kind of text block, keeping the words. Secrets and spoilers never convert. */
  turnInto(id: string, type: 'paragraph' | 'heading' | 'quote' | 'callout' | 'toggle'): boolean {
    const p = this.page
    const i = this.#index(id)
    if (!p?.content || i < 0 || !this.can('blocks') || !this.can('text')) return false
    const b = p.content[i]
    if (!isTextType(b.type) || b.type === type) return false
    const text = (b as Of<'paragraph'>).text
    p.content[i] = type === 'toggle' ? { id, type, text, body: '' } : { id, type, text }
    this.#changed()
    return true
  }

  setIcon(icon: string) {
    const p = this.page
    if (!p || !this.can('text') || (icon !== '' && !isEmoji(icon))) return
    p.icon = icon
    this.#changed()
  }

  setCover(key: string) {
    const p = this.page
    if (!p || !this.can('text') || !isCover(key)) return
    p.cover = key
    this.#changed()
  }

  setLang(id: string, lang: string) {
    const b = this.#block(id, 'code')
    if (b && this.can('text')) {
      b.lang = lang
      this.#changed()
    }
  }

  // checklist
  toggleItem(id: string, itemId: string) {
    const item = this.#block(id, 'checklist')?.items.find((i) => i.id === itemId)
    if (item && this.can('checklist')) {
      item.done = !item.done
      this.#changed()
    }
  }

  setItemText(id: string, itemId: string, text: string) {
    const item = this.#block(id, 'checklist')?.items.find((i) => i.id === itemId)
    if (item && this.can('text')) {
      item.text = text.slice(0, MAX_TEXT)
      this.#changed()
    }
  }

  addItem(id: string, afterItemId: string | null = null): string | null {
    const b = this.#block(id, 'checklist')
    if (!b || !this.can('blocks') || b.items.length >= MAX_ITEMS) return null
    const item = { id: newId('i'), text: '', done: false }
    const at = afterItemId === null ? b.items.length : b.items.findIndex((i) => i.id === afterItemId) + 1
    b.items.splice(at, 0, item)
    this.#changed()
    return item.id
  }

  /** Removes an item; the last one takes the whole checklist block with it. */
  removeItem(id: string, itemId: string) {
    const b = this.#block(id, 'checklist')
    if (!b || !this.can('blocks')) return
    if (b.items.length <= 1) return this.remove(id)
    b.items = b.items.filter((i) => i.id !== itemId)
    this.#changed()
  }

  // table
  setLabel(id: string, colId: string, label: string) {
    const col = this.#block(id, 'table')?.cols.find((c) => c.id === colId)
    if (col && this.can('text')) {
      col.label = label.slice(0, 80)
      this.#changed()
    }
  }

  setCell(id: string, row: number, colId: string, text: string) {
    const r = this.#block(id, 'table')?.rows[row]
    if (r && this.can('text')) {
      r[colId] = text.slice(0, 2000)
      this.#changed()
    }
  }

  addCol(id: string): string | null {
    const b = this.#block(id, 'table')
    if (!b || !this.can('tables') || b.cols.length >= MAX_COLS) return null
    const col = { id: newId('c'), label: `Coluna ${b.cols.length + 1}`, w: 160 }
    b.cols.push(col)
    b.rows.forEach((r) => (r[col.id] = ''))
    this.#changed()
    return col.id
  }

  addRow(id: string) {
    const b = this.#block(id, 'table')
    if (!b || !this.can('tables') || b.rows.length >= MAX_ROWS) return
    b.rows.push(Object.fromEntries(b.cols.map((c) => [c.id, ''])))
    this.#changed()
  }

  /** A table keeps at least one column and one row. */
  removeCol(id: string, colId: string) {
    const b = this.#block(id, 'table')
    if (!b || !this.can('tables') || b.cols.length <= 1) return
    b.cols = b.cols.filter((c) => c.id !== colId)
    b.rows.forEach((r) => delete r[colId])
    this.#changed()
  }

  removeRow(id: string, row: number) {
    const b = this.#block(id, 'table')
    if (!b || !this.can('tables') || b.rows.length <= 1 || row < 0 || row >= b.rows.length) return
    b.rows.splice(row, 1)
    this.#changed()
  }

  resizeCol(id: string, colId: string, width: number) {
    const col = this.#block(id, 'table')?.cols.find((c) => c.id === colId)
    if (col && this.can('tables') && Number.isFinite(width)) {
      col.w = Math.min(MAX_COL_WIDTH, Math.max(MIN_COL_WIDTH, Math.round(width)))
      this.#changed()
    }
  }

  moveCol(id: string, from: number, at: number) {
    const b = this.#block(id, 'table')
    if (b && this.can('tables') && moveItem(b.cols, from, at)) this.#changed()
  }

  moveRow(id: string, from: number, at: number) {
    const b = this.#block(id, 'table')
    if (b && this.can('tables') && moveItem(b.rows, from, at)) this.#changed()
  }

  // image
  setImage(id: string, name: string | null, src: string | null) {
    const b = this.#block(id, 'image')
    if (!b || !this.can('images')) return
    if (b.src && b.src !== src) URL.revokeObjectURL?.(b.src)
    b.name = name
    b.src = src
    this.#changed()
  }

  // spoiler / secure
  reveal(id: string, open: boolean) {
    this.revealed[id] = open
  }

  // tags
  addTag(name: string, color: TagColor = 'accent'): boolean {
    const p: NotePage | undefined = this.page
    if (!p || !this.can('tags')) return false
    const tag = this.ws.addTag(name.slice(0, MAX_TAG_NAME), color)
    if (!tag || p.tags.includes(tag.id)) return false
    p.tags.push(tag.id)
    this.#changed()
    return true
  }

  removeTag(tagId: string) {
    const p = this.page
    if (!p || !this.can('tags') || !p.tags.includes(tagId)) return
    p.tags = p.tags.filter((t) => t !== tagId)
    this.#changed()
  }

  // sharing: the owner adds and removes; somebody with the "share" permission may only add
  get shares() {
    return this.page?.shares ?? []
  }

  share(userIds: string[], perms: PermKey[]): number {
    return this.can('share') ? this.ws.sharePage(this.id, userIds, perms) : 0
  }

  setShare(userId: string, perms: PermKey[]) {
    if (this.isOwner) this.ws.setShare(this.id, userId, perms)
  }

  unshare(userId: string) {
    if (this.isOwner) this.ws.unshare(this.id, userId)
  }

  unshareAll() {
    if (this.isOwner) this.ws.unshareAll(this.id)
  }
}
