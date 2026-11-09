import { excerptOf, fileIdsOf, newId, type Block } from './blocks'
import { files } from './files.svelte'
import type { NotesStore } from '../storage/notesStore'
import { Persistence } from '../storage/persistence'
import { canVault } from '../capabilities'
import { ALL_PERMS, normalizePerms, type PermKey } from './permissions'
import { fold } from './text'
import { toast } from './toast.svelte'
import { ME, type User } from './users'

export type View = 'all' | 'shared' | 'vault' | 'trash'
export type Sort = 'recent' | 'az'
export type Layout = 'grid' | 'list'
export type TagColor = 'accent' | 'rust' | 'blue' | 'gold' | 'plum' | 'teal'

export const TAG_COLORS: TagColor[] = ['accent', 'rust', 'blue', 'gold', 'plum', 'teal']

export interface Tag {
  id: string
  name: string
  color: TagColor
}

export interface NotePage {
  id: string
  title: string
  excerpt: string
  tags: string[]
  updated: number
  /** Number of blocks (kept in step with `content` once the page has been opened in the editor). */
  blocks: number
  /** The body; null while a page was never opened (the editor then starts it from the excerpt). */
  content: Block[] | null
  created: number
  /** Who shared it with me; null for my own pages. */
  sharedBy: string | null
  /** What I may do with a page that was shared with me (my own pages allow everything). */
  myPerms: PermKey[]
  /** Who I shared my own page with. */
  shares: Share[]
  /** Lives in the vault: its content is hidden until the vault is unlocked. */
  locked: boolean
  trashed: boolean
  pinned: boolean
  /** One emoji, or '' for none. */
  icon: string
  /** A cover spec (see `cover.ts`), or '' for none. */
  cover: string
}

/** One person a page was shared with, and what they may do with it. */
export interface Share {
  userId: string
  perms: PermKey[]
}

export interface Settings {
  useTrash: boolean
  /** Days a trashed page is kept. */
  retention: number
}

export interface PageGroup {
  key: string
  /** null: no visible heading (a single flat list). */
  label: string | null
  pages: NotePage[]
}

export { fold }

const MAX_TITLE = 120
export const MAX_TAG_NAME = 24
/** The master password only needs this many characters in the prototype (the real one is checked by Argon2id). */
export const MIN_VAULT_PASSWORD = 4

/** The state of the dashboard. One instance per screen, so tests start clean. */
export class Workspace {
  pages = $state<NotePage[]>([])
  tags = $state<Tag[]>([])
  users = $state<User[]>([])
  settings = $state<Settings>({ useTrash: true, retention: 30 })
  vaultUnlocked = $state(false)
  /** The person chose "Continuar sem login": there is no server, so nothing can be shared. */
  local = $state(false)
  /** How the person's own pages are credited: their username when signed in, "Você" without an account. */
  ownerName = $state('Você')
  view = $state<View>('all')
  sort = $state<Sort>('recent')
  layout = $state<Layout>('grid')
  query = $state('')
  tagFilter = $state<string | null>(null)
  #seq = 100
  /** Where the pages are kept between visits; null when nothing is saved (the demo, or a browser without storage). */
  persist: Persistence | null = null
  /** The saved pages are being read. */
  loading = $state(false)
  /** Pages whose body is on disk, so `content === null` means "not read yet" and not "empty". */
  #stored = new Set<string>()
  /** How many screens have each page's body open; it goes back to disk when the last one leaves. */
  #open = new Map<string, number>()

  /**
   * Starts saving into `store` and replaces the pages with what it holds. Only the list is read: bodies come with
   * `load`, so a workspace of thousands of pages costs what its cards cost.
   */
  async attach(store: NotesStore): Promise<void> {
    await this.detach()
    this.loading = true
    try {
      const saved = await store.loadAll()
      const made = this.pages
      const taken = new Set(saved.pages.map((p) => p.id))
      for (const id of taken) {
        const n = /^n(\d+)$/.exec(id)
        if (n) this.#seq = Math.max(this.#seq, Number(n[1]))
      }
      // a page made while the list was loading may have been given an id the saved ones already use
      for (const p of made) if (taken.has(p.id)) p.id = `n${++this.#seq}`
      if (saved.tags) this.tags = saved.tags
      if (saved.settings) this.settings = saved.settings
      this.pages = [...made, ...saved.pages.map((p): NotePage => ({ ...p, content: null }))]
      for (const id of taken) this.#stored.add(id)
      this.persist = new Persistence(store, this)
      this.persist.onerror = () => toast.show('Não foi possível guardar neste navegador; as mudanças podem se perder')
      // whatever was made while the list was loading still has to be saved
      for (const p of made) this.persist.mark(p.id)
      void navigator.storage?.persist?.()
    } catch (e) {
      store.close()
      toast.show('Este navegador não deixou guardar as notas; elas valem só até fechar a aba')
      console.error(e)
    } finally {
      this.loading = false
    }
  }

  /** Closes the account: writes what is left, stops saving and drops every note from memory. */
  async close(): Promise<void> {
    const done = this.detach()
    this.pages = []
    this.tags = []
    this.users = []
    this.tagFilter = null
    this.query = ''
    this.vaultUnlocked = false
    await done
  }

  /** Writes what is left and stops saving. */
  async detach(): Promise<void> {
    const p = this.persist
    this.persist = null
    this.#stored.clear()
    this.#open.clear()
    await p?.close()
  }

  /** Whether a screen may show this page now: its body is in memory, or there is nothing to read (or no such page). */
  bodyIn(id: string): boolean {
    const p = this.page(id)
    return !p || !!p.content || !this.persist || !this.#stored.has(id)
  }

  /** Brings the body of a page into memory (call it before a screen shows the page). False when the disk could not be read. */
  async load(id: string): Promise<boolean> {
    const p = this.page(id)
    if (!p) return true
    this.#open.set(id, (this.#open.get(id) ?? 0) + 1)
    if (p.content || !this.persist || !this.#stored.has(id)) return true
    try {
      const blocks = await this.persist.store.loadBody(id)
      // the page may have been opened and changed by someone else while this was reading
      if (!p.content) p.content = blocks ?? []
      return true
    } catch (e) {
      console.error(e)
      toast.show('Não foi possível abrir a página')
      this.#open.set(id, Math.max(0, (this.#open.get(id) ?? 1) - 1))
      return false
    }
  }

  /** The screen is done with the page: once it is written, the body leaves memory. */
  release(id: string) {
    const left = (this.#open.get(id) ?? 1) - 1
    if (left > 0) return void this.#open.set(id, left)
    this.#open.delete(id)
    const persist = this.persist
    if (!persist) return
    // only what was edited is written back (edits mark the page themselves): looking at a page must cost no write
    void persist.flush().then(() => {
      const p = this.page(id)
      if (p?.content && !persist.pending(id) && this.persist === persist && !this.#open.has(id)) {
        p.content = null
        this.#stored.add(id)
      }
    })
  }

  /** Runs `fn` with every body in memory (an export needs them all), then lets the ones nobody had open go again. */
  async withBodies<T>(fn: () => T): Promise<T> {
    const ids = this.pages.filter((p) => !p.content && this.#stored.has(p.id)).map((p) => p.id)
    const ok = await Promise.all(ids.map((id) => this.load(id)))
    try {
      return fn()
    } finally {
      ids.forEach((id, i) => ok[i] && this.release(id))
    }
  }

  /** Local mode (no login): the person's own notes start empty. The demo pages, tags and people go (the vault stays, empty), and there is no sharing. */
  goLocal() {
    this.#startEmpty(true)
  }

  /** A signed-in account: its notes start empty too (they come from the account's own database), with the "shared with me" list kept. */
  goAccount() {
    this.#startEmpty(false)
  }

  #startEmpty(local: boolean) {
    // first: the pages are about to be emptied, and whatever was waiting to be saved must be copied before that
    void this.detach()
    this.local = local
    this.pages = []
    this.tags = []
    this.users = []
    this.tagFilter = null
    this.query = ''
    this.vaultUnlocked = false
    if (local && this.view === 'shared') this.view = 'all'
  }

  live = $derived(this.pages.filter((p) => !p.trashed))
  /** My own pages: "all pages" never lists what others shared with me. */
  mine = $derived(this.live.filter((p) => !p.sharedBy))
  counts = $derived({
    all: this.mine.length,
    shared: this.live.length - this.mine.length,
    vault: this.live.filter((p) => p.locked).length,
    trash: this.pages.length - this.live.length,
  })
  tagCounts = $derived(
    Object.fromEntries(this.tags.map((t) => [t.id, this.mine.filter((p) => p.tags.includes(t.id)).length])) as Record<string, number>,
  )

  /** What the current view shows, after search, tag filter and sort. */
  visible = $derived.by(() => {
    if (this.view === 'vault') return []
    const q = fold(this.query.trim())
    const base =
      this.view === 'trash'
        ? this.pages.filter((p) => p.trashed)
        : this.view === 'shared'
          ? this.live.filter((p) => p.sharedBy)
          : this.mine
    const list = base.filter(
      (p) =>
        (!this.tagFilter || p.tags.includes(this.tagFilter)) &&
        (!q || fold(p.title).includes(q) || (this.#readable(p) && fold(p.excerpt).includes(q))),
    )
    return list.sort((a, b) => (this.sort === 'az' ? a.title.localeCompare(b.title, 'pt-BR') : b.updated - a.updated))
  })

  /** The pages that live in the vault. */
  visibleVault = $derived.by(() => {
    const q = fold(this.query.trim())
    // a locked vault matches on titles only: the content is not readable
    return this.live
      .filter((p) => p.locked && (!q || fold(p.title).includes(q) || (this.vaultUnlocked && fold(p.excerpt).includes(q))))
      .sort((a, b) => b.updated - a.updated)
  })

  /** A page's text may be read (searched, shown on a card) unless it is in a vault that is still locked. */
  #readable(p: NotePage) {
    return !p.locked || this.vaultUnlocked
  }

  /**
   * `visible` split into sections: pinned first, then by date (or one list when sorted A–Z). Search results and the
   * trash stay a single flat list, where sections would only hide matches.
   */
  groups = $derived.by((): PageGroup[] => {
    const list = this.visible
    if (this.view === 'trash' || this.query.trim()) return [{ key: 'all', label: null, pages: list }]
    const out: PageGroup[] = []
    const pinned = list.filter((p) => p.pinned)
    const rest = list.filter((p) => !p.pinned)
    if (pinned.length) out.push({ key: 'pinned', label: 'Fixadas', pages: pinned })
    if (this.sort === 'az') {
      if (rest.length) out.push({ key: 'rest', label: pinned.length ? 'Outras' : null, pages: rest })
      return out
    }
    const startOfDay = new Date().setHours(0, 0, 0, 0)
    const buckets: [string, string, number][] = [
      ['today', 'Hoje', startOfDay],
      ['week', 'Esta semana', startOfDay - 6 * 86_400_000],
      ['month', 'Últimos 30 dias', startOfDay - 29 * 86_400_000],
      ['older', 'Mais antigas', -Infinity],
    ]
    let remaining = rest
    for (const [key, label, from] of buckets) {
      const here = remaining.filter((p) => p.updated >= from)
      remaining = remaining.filter((p) => p.updated < from)
      if (here.length) out.push({ key, label, pages: here })
    }
    return out
  })

  tag(id: string) {
    return this.tags.find((t) => t.id === id)
  }

  go(view: View) {
    // the vault does not exist on a page without crypto.subtle (plain HTTP)
    if (view === 'vault' && !canVault()) return
    this.view = view
    this.tagFilter = null
  }

  toggleTagFilter(id: string) {
    this.tagFilter = this.tagFilter === id ? null : id
    // a tag filters my own pages
    if (this.view === 'vault' || this.view === 'shared') this.view = 'all'
  }

  clearFilters() {
    this.query = ''
    this.tagFilter = null
  }

  /** Brings a page into view (the prototype has no editor yet): its view, no tag filter, its title as the search. */
  reveal(id: string) {
    const p = this.pages.find((x) => x.id === id)
    if (!p) return
    this.view = p.trashed ? 'trash' : p.sharedBy ? 'shared' : 'all'
    this.tagFilter = null
    this.query = p.title
  }

  /** Adds an empty page at the top of "all pages" and returns it. */
  newPage(title = 'Sem título'): NotePage {
    const page: NotePage = {
      id: `n${++this.#seq}`,
      title: title.trim().slice(0, MAX_TITLE) || 'Sem título',
      excerpt: '',
      tags: this.tagFilter ? [this.tagFilter] : [],
      updated: Date.now(),
      blocks: 0,
      content: [],
      created: Date.now(),
      sharedBy: null,
      myPerms: [...ALL_PERMS],
      shares: [],
      locked: false,
      trashed: false,
      pinned: false,
      icon: '',
      cover: '',
    }
    this.pages.unshift(page)
    this.persist?.mark(page.id)
    this.view = 'all'
    this.query = ''
    this.sort = 'recent'
    return page
  }

  page(id: string) {
    return this.pages.find((p) => p.id === id)
  }

  /** The body of a page; one that was never opened starts as a single paragraph with its excerpt. */
  contentOf(id: string): Block[] | null {
    const p = this.page(id)
    if (!p) return null
    // saved but not read yet: inventing a body here would overwrite the real one on the next save
    if (!p.content && this.persist && this.#stored.has(id)) return null
    if (!p.content) p.content = p.excerpt ? [{ id: `${p.id}-b0`, type: 'paragraph', text: p.excerpt }] : []
    return p.content
  }

  /** After an edit: the card shows the new excerpt, block count and time. */
  touch(id: string) {
    const p = this.page(id)
    if (!p) return
    p.updated = Date.now()
    if (p.content) {
      p.blocks = p.content.length
      p.excerpt = excerptOf(p.content)
    }
    this.persist?.mark(id)
  }

  /** Other pages that share tags with this one, the ones sharing the most first. Vault pages are never suggested. */
  related(id: string, limit = 5): NotePage[] {
    const page = this.page(id)
    if (!page || page.tags.length === 0) return []
    const overlap = (p: NotePage) => p.tags.filter((t) => page.tags.includes(t)).length
    return this.live
      .filter((p) => p.id !== id && !p.locked && overlap(p) > 0)
      .sort((a, b) => overlap(b) - overlap(a) || b.updated - a.updated)
      .slice(0, limit)
  }

  /**
   * A copy of the page that belongs to me: same body and tags, no sharing, not pinned. Images are left out (their
   * temporary links belong to the original); returns the copy and how many images stayed behind.
   */
  duplicate(id: string): { page: NotePage; images: number } | null {
    const src = this.page(id)
    if (!src) return null
    const body: Block[] = JSON.parse(JSON.stringify(this.contentOf(id) ?? []))
    let images = 0
    for (const b of body) {
      b.id = newId()
      if (b.type === 'image' && (b.src || b.mediaId)) {
        images++
        b.src = null
        b.name = null
        delete b.mediaId
      }
    }
    const now = Date.now()
    const copy: NotePage = {
      ...JSON.parse(JSON.stringify({ ...src, content: null })),
      id: `n${++this.#seq}`,
      title: `${src.title} (cópia)`.slice(0, MAX_TITLE),
      content: body,
      blocks: body.length,
      created: now,
      updated: now,
      sharedBy: null,
      myPerms: [...ALL_PERMS],
      shares: [],
      pinned: false,
      trashed: false,
    }
    this.pages.unshift(copy)
    this.persist?.mark(copy.id)
    return { page: this.page(copy.id)!, images }
  }

  togglePin(id: string) {
    const p = this.pages.find((x) => x.id === id)
    if (p) p.pinned = !p.pinned
    this.persist?.mark(id)
  }

  /** Moves a page to the trash, or deletes it for good when the trash is turned off in the settings. */
  trash(id: string) {
    // vault pages never wait in the trash; a trash that is turned off deletes at once too
    if (!this.settings.useTrash || this.page(id)?.locked) {
      this.pages = this.pages.filter((p) => p.id !== id)
      this.persist?.mark(id)
      return
    }
    const p = this.pages.find((x) => x.id === id)
    if (p) p.trashed = true
    this.persist?.mark(id)
  }

  restore(id: string) {
    const p = this.pages.find((x) => x.id === id)
    if (p) p.trashed = false
    this.persist?.mark(id)
  }

  emptyTrash() {
    const gone = this.pages.filter((p) => p.trashed)
    this.pages = this.pages.filter((p) => !p.trashed)
    gone.forEach((p) => this.persist?.mark(p.id))
    this.#dropFiles(gone)
  }

  /** Told which files only the pages deleted for good used, so the server can drop them at once. */
  filesGone: (ids: string[]) => void = (ids) => files.remove(ids)

  #dropFiles(gone: NotePage[]) {
    // only my own pages: a page shared with me keeps its files with whoever sent it
    const ids = fileIdsOf(gone.filter((p) => !p.sharedBy).flatMap((p) => p.content ?? []))
    if (!ids.length) return
    const kept = new Set(fileIdsOf(this.pages.flatMap((p) => p.content ?? [])))
    const alone = ids.filter((id) => !kept.has(id))
    if (alone.length) this.filesGone(alone)
  }

  /** Returns the new tag, or the existing one when the name is already taken; null for an empty name. */
  addTag(name: string, color: TagColor = 'accent'): Tag | null {
    const clean = name.trim().replace(/\s+/g, '-').slice(0, MAX_TAG_NAME)
    if (!clean) return null
    const id = fold(clean)
    const existing = this.tags.find((t) => t.id === id)
    if (existing) return existing
    const tag: Tag = { id, name: clean.toLowerCase(), color: TAG_COLORS.includes(color) ? color : 'accent' }
    this.tags.push(tag)
    this.persist?.markMeta()
    return tag
  }

  /** Prototype: any password of at least MIN_VAULT_PASSWORD characters opens it; nothing is decrypted yet. */
  unlockVault(password: string): 'ok' | 'short' | 'unavailable' {
    if (!canVault()) return 'unavailable'
    if (password.trim().length < MIN_VAULT_PASSWORD) return 'short'
    this.vaultUnlocked = true
    // the text of vault pages is not kept in the list on disk: bring the excerpts back now that they may be read
    void this.persist?.store.loadVaultExcerpts().then((excerpts) => {
      for (const p of this.pages) if (p.locked && !p.excerpt) p.excerpt = excerpts.get(p.id) ?? ''
    })
    return 'ok'
  }

  lockVault() {
    this.vaultUnlocked = false
  }

  deleteForever(id: string) {
    const gone = this.pages.filter((p) => p.id === id)
    this.pages = this.pages.filter((p) => p.id !== id)
    this.persist?.mark(id)
    this.#dropFiles(gone)
  }

  /** A new, empty vault page. Only while the vault is unlocked. */
  addVaultEntry(): NotePage | null {
    if (!this.vaultUnlocked) return null
    const page = this.newPage('Nova entrada segura')
    page.locked = true
    // the vault is where it lives: stay there
    this.view = 'vault'
    return page
  }

  user(id: string) {
    return this.users.find((u) => u.id === id)
  }

  /** Gives these people access; unknown people, myself and people who already have it are skipped. */
  sharePage(id: string, userIds: string[], perms: PermKey[]): number {
    const p = this.page(id)
    if (!p) return 0
    const clean = normalizePerms(perms)
    let added = 0
    for (const userId of new Set(userIds)) {
      if (userId === ME || !this.user(userId) || p.shares.some((s) => s.userId === userId)) continue
      p.shares.push({ userId, perms: [...clean] })
      added++
    }
    if (added) this.persist?.mark(id)
    return added
  }

  setShare(id: string, userId: string, perms: PermKey[]) {
    const share = this.page(id)?.shares.find((s) => s.userId === userId)
    if (share) share.perms = normalizePerms(perms)
    this.persist?.mark(id)
  }

  unshare(id: string, userId: string) {
    const p = this.page(id)
    if (p) p.shares = p.shares.filter((s) => s.userId !== userId)
    this.persist?.mark(id)
  }

  unshareAll(id: string) {
    const p = this.page(id)
    if (p) p.shares = []
    this.persist?.mark(id)
  }

  saveSettings(next: Settings) {
    this.settings = { useTrash: next.useTrash, retention: Math.min(90, Math.max(7, Math.round(next.retention) || 30)) }
    this.persist?.markMeta()
  }
}

const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

export function formatDate(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getDate()).padStart(2, '0')} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`
}

/** The small right-hand note of a card: where it lives, who shared it, or its size. */
export function pageMeta(p: NotePage): string {
  if (p.locked) return 'cofre'
  if (p.sharedBy) return `por ${p.sharedBy}`
  return `${p.blocks} ${p.blocks === 1 ? 'bloco' : 'blocos'}`
}
