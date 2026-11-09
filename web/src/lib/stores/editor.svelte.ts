import {
  checklistProgress,
  outline,
  pageStats,
  makeBlock,
  moveItem,
  newId,
  MAX_BLOCKS,
  MAX_INDENT,
  MAX_COL_WIDTH,
  MAX_COLS,
  MAX_ITEMS,
  MAX_ROWS,
  MAX_TEXT,
  MIN_COL_WIDTH,
  isTextType,
  isTone,
  isUrlBlock,
  blockTypeForFile,
  fileIdsOf,
  levelOf,
  type Block,
  type BlockType,
  type CalloutTone,
  type HeadingLevel,
} from './blocks'
import { isCover } from './cover'
import { files as fileService, type FilesPort, type Upload } from './files.svelte'
import { toast } from './toast.svelte'
import { isEmoji } from './emoji'
import { safeUrl } from './inline'
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
  /** Files being sent into blocks right now (block id to upload); a failed one stays until it is dismissed or tried again. */
  uploading = $state<Record<string, Upload>>({})
  /** The file service (a test can stand in for it). */
  files: FilesPort = fileService
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
  insert(type: BlockType, afterId: string | null = null, opts: { level?: HeadingLevel; toggle?: boolean } = {}): Block | null {
    const p = this.page
    if (!p?.content || !this.can('blocks') || p.content.length >= MAX_BLOCKS) return null
    if (type === 'image' && !this.can('images')) return null
    const block = makeBlock(type, opts)
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
    const [gone] = p.content.splice(i, 1)
    this.#changed()
    if (gone.type === 'image' && gone.mediaId) this.#dropMedia(gone.mediaId)
    this.#release(fileIdsOf([gone]))
    this.#cancelUpload(id)
  }

  /** Whether any block of any open page still points at this file. */
  #inUse(fileId: string): boolean {
    return this.ws.pages.some((page) => page.content && fileIdsOf(page.content).includes(fileId))
  }

  /** Tells the server which files nothing uses any more (it deletes them after a grace period). */
  #release(ids: string[]) {
    for (const id of ids) if (!this.#inUse(id)) this.files.orphan(id, true)
  }

  #cancelUpload(blockId: string) {
    const u = this.uploading[blockId]
    if (!u) return
    if (u.status === 'queued' || u.status === 'sending') this.files.cancel(u.key)
    delete this.uploading[blockId]
  }

  /**
   * Sends a file into a block. When it arrives the block becomes what suits the file: an image, a video, a sound, a PDF, or
   * a file card for the rest. False when it cannot start (nobody signed in, no permission).
   */
  uploadInto(blockId: string, file: File): boolean {
    const b = this.blocks.find((x) => x.id === blockId)
    if (!b || !this.can('blocks') || (b.type === 'image' && !this.can('images'))) return false
    if (!this.files.available) {
      toast.show('Entre em um servidor para enviar arquivos')
      return false
    }
    if (file.size === 0) {
      toast.show('O arquivo está vazio')
      return false
    }
    this.#cancelUpload(blockId)
    const pageId = this.id
    this.uploading[blockId] = this.files.start(file, (info) => this.#arrived(pageId, blockId, info))
    return true
  }

  /** Gives up on a file that is being sent or that failed. */
  dismissUpload(blockId: string) {
    this.#cancelUpload(blockId)
  }

  #arrived(pageId: string, blockId: string, info: { id: string; name: string; size: number; mime: string; level: number }) {
    delete this.uploading[blockId]
    const page = this.ws.page(pageId)
    const i = page?.content ? page.content.findIndex((x) => x.id === blockId) : -1
    if (!page?.content || i < 0) {
      // the block (or the whole page) went away while the file travelled: nothing uses it
      this.files.orphan(info.id, true)
      return
    }
    const before = fileIdsOf([page.content[i]])
    const type = blockTypeForFile(info.mime, info.level)
    const level = (info.level === 1 || info.level === 2 ? info.level : 3) as 1 | 2 | 3
    page.content[i] =
      type === 'image'
        ? { id: blockId, type, name: info.name || null, src: null, fileId: info.id }
        : type === 'file'
          ? { id: blockId, type, fileId: info.id, name: info.name, size: info.size, mime: info.mime, level }
          : { id: blockId, type, url: '', title: info.name, fileId: info.id }
    if (pageId === this.id) this.#changed()
    else this.ws.touch(pageId)
    this.#release(before.filter((f) => f !== info.id))
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
    if (!b || !('text' in b)) return null
    const at = Math.min(Math.max(0, caret), b.text.length)
    return this.splitText(id, b.text.slice(0, at), b.text.slice(at))
  }

  /** The same, with the two halves already cut (a rich-text engine knows where its marks begin and end). */
  splitText(id: string, head: string, tail: string): Block | null {
    const b = this.blocks.find((x) => x.id === id)
    if (!b || !['paragraph', 'heading', 'quote', 'callout', 'toggle', 'spoiler', 'bullet', 'numbered'].includes(b.type) || !('text' in b) || !this.can('text')) return null
    // Enter in a list item makes another item of the same list; anywhere else, a paragraph
    const kind = b.type === 'bullet' || b.type === 'numbered' ? b.type : 'paragraph'
    const made = this.insert(kind, id)
    if (!made || made.type !== kind || !('text' in made)) return null
    if ((b.type === 'bullet' || b.type === 'numbered') && (made.type === 'bullet' || made.type === 'numbered')) made.indent = b.indent ?? 0
    b.text = head.slice(0, MAX_TEXT)
    made.text = tail.slice(0, MAX_TEXT)
    this.#changed()
    return made
  }

  setBody(id: string, body: string) {
    const found = this.blocks.find((x) => x.id === id)
    const b = found?.type === 'toggle' || (found?.type === 'heading' && found.toggle) ? found : undefined
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
    // an image picked in this session has a temporary address that belongs to the original; one kept on the server can be shared
    if (src.type === 'image' && !src.fileId) return null // a picture kept on this device belongs to one block
    const copy: Block = JSON.parse(JSON.stringify(src))
    copy.id = newId()
    if (copy.type === 'checklist') copy.items.forEach((item) => (item.id = newId('i')))
    p.content.splice(i + 1, 0, copy)
    this.#changed()
    return p.content[i + 1]
  }

  /** Changes a text block into another kind of text block, keeping the words. Secrets and spoilers never convert. */
  turnInto(id: string, type: 'paragraph' | 'heading' | 'quote' | 'callout' | 'toggle' | 'bullet' | 'numbered', opts: { level?: HeadingLevel; toggle?: boolean } = {}): boolean {
    const p = this.page
    const i = this.#index(id)
    if (!p?.content || i < 0 || !this.can('blocks') || !this.can('text')) return false
    const b = p.content[i]
    if (!isTextType(b.type)) return false
    const level = opts.level ?? 2
    const wantsToggle = type === 'heading' && !!opts.toggle
    if (b.type === type && (type !== 'heading' || (levelOf(b as Of<'heading'>) === level && !!(b as Of<'heading'>).toggle === wantsToggle))) return false
    const text = (b as Of<'paragraph'>).text
    p.content[i] =
      type === 'toggle' ? { id, type, text, body: '' } : type === 'heading' ? { id, type, text, ...(level === 2 ? {} : { level }), ...(wantsToggle ? { toggle: true as const, body: (b.type === 'heading' ? (b.body ?? '') : '') } : {}) } : type === 'bullet' || type === 'numbered' ? { id, type, text, indent: 0 } : { id, type, text }
    this.#changed()
    return true
  }

  /** Nests a list item one level deeper (+1) or brings it back (-1). False when it cannot move. */
  indent(id: string, delta: -1 | 1): boolean {
    const b = this.blocks.find((x) => x.id === id)
    if (!b || (b.type !== 'bullet' && b.type !== 'numbered') || !this.can('text')) return false
    const next = Math.min(Math.max((b.indent ?? 0) + delta, 0), MAX_INDENT)
    if (next === (b.indent ?? 0)) return false
    b.indent = next
    this.#changed()
    return true
  }

  /** Enter on an empty list item: it comes out one level, and from the first level it stops being a list item. */
  leaveList(id: string): boolean {
    const b = this.blocks.find((x) => x.id === id)
    if (!b || (b.type !== 'bullet' && b.type !== 'numbered')) return false
    return (b.indent ?? 0) > 0 ? this.indent(id, -1) : this.turnInto(id, 'paragraph')
  }

  setTone(id: string, tone: CalloutTone) {
    const b = this.#block(id, 'callout')
    if (b && this.can('text') && isTone(tone)) {
      if (tone === 'info') delete b.tone
      else b.tone = tone
      this.#changed()
    }
  }

  /**
   * Sets the address (and the title) of a link card, a video, an audio or a PDF. An address that is not safe is refused
   * (false) and nothing changes; media and PDFs take http(s) only, since an e-mail address plays nothing.
   */
  setUrl(id: string, url: string, title = ''): boolean {
    const b = this.blocks.find((x) => x.id === id)
    const safe = safeUrl(url)
    if (!b || !isUrlBlock(b) || !this.can('text') || !safe) return false
    if (b.type !== 'bookmark' && !/^https?:/i.test(safe)) return false
    b.url = safe
    b.title = title.replace(/\s+/g, ' ').trim().slice(0, 200)
    this.#changed()
    return true
  }

  /** Points a page link at another page of the workspace. Not itself, not a page in the trash, not one in the vault. */
  setPageLink(id: string, pageId: string): boolean {
    const b = this.#block(id, 'pagelink')
    const target = this.ws.page(pageId)
    if (!b || !this.can('text') || !target || target.id === this.id || target.trashed || target.locked) return false
    b.pageId = target.id
    b.title = target.title
    this.#changed()
    return true
  }

  /**
   * Keeps the name a page link remembers in step with the page (the card shows the live one; the remembered one goes into
   * exports). A page that moved into the vault is forgotten by name, so an export never carries it out.
   */
  syncPageLink(id: string): void {
    const b = this.#block(id, 'pagelink')
    if (!b || !this.can('text')) return
    const target = this.ws.page(b.pageId)
    const name = !target ? b.title : target.locked ? '' : target.title
    if (b.title !== name) {
      b.title = name
      this.#changed()
    }
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
    const had = b.fileId
    const stored = b.mediaId
    b.name = name
    b.src = src
    delete b.fileId
    delete b.mediaId
    this.#changed()
    if (had) this.#release([had])
    if (stored) this.#dropMedia(stored)
  }

  /** A picture picked on this device: kept in the browser's media store when there is one, otherwise only for this session. */
  async setImageFile(id: string, file: File): Promise<boolean> {
    const persist = this.ws.persist
    if (!persist) {
      this.setImage(id, file.name, URL.createObjectURL(file))
      return true
    }
    if (!this.#block(id, 'image') || !this.can('images')) return false
    let mediaId: string
    try {
      mediaId = await persist.store.putMedia(this.id, file)
    } catch {
      toast.show('Não foi possível guardar a imagem neste navegador')
      return false
    }
    const b = this.#block(id, 'image')
    if (!b || !this.can('images')) {
      // the block (or the page) went away while the picture was being written
      this.#dropMedia(mediaId)
      return false
    }
    const had = b.fileId
    const before = b.mediaId
    if (b.src) URL.revokeObjectURL?.(b.src)
    b.name = file.name
    b.src = null
    b.mediaId = mediaId
    delete b.fileId
    this.#changed()
    if (had) this.#release([had])
    if (before) this.#dropMedia(before)
    return true
  }

  #dropMedia(mediaId: string) {
    void this.ws.persist?.store.deleteMedia(mediaId).catch(() => {})
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
