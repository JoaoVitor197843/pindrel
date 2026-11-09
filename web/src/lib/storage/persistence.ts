import type { NotesStore, PageWrite, StoredPage } from './notesStore'
import type { NotePage, Settings, Tag } from '../stores/workspace.svelte'

/** What the persistence needs to read from the workspace. */
export interface Source {
  page(id: string): NotePage | undefined
  tags: Tag[]
  settings: Settings
}

const DELAY_MS = 400

// reactive proxies cannot be structured-cloned into IndexedDB, and the copy must not change under a write in flight
const plain = <T>(v: T): T => JSON.parse(JSON.stringify(v))

/**
 * Writes what changed, a moment after it changed. A typing burst is one write; the whole batch goes in one transaction
 * and the copy is taken at the time of the call, so what lands on disk is what the screen showed then.
 */
export class Persistence {
  readonly store: NotesStore
  #src: Source
  #dirty = new Set<string>()
  #metaDirty = false
  #timer: ReturnType<typeof setTimeout> | undefined
  #chain: Promise<void> = Promise.resolve()
  #failed = false
  /** Told once when a write fails (a full disk, a private window); cleared by the next one that works. */
  onerror: (e: unknown) => void = () => {}
  #leave = () => {
    if (document.visibilityState === 'hidden') void this.flush()
  }
  #hide = () => void this.flush()

  constructor(store: NotesStore, src: Source) {
    this.store = store
    this.#src = src
    document.addEventListener('visibilitychange', this.#leave)
    window.addEventListener('pagehide', this.#hide)
  }

  mark(id: string) {
    this.#dirty.add(id)
    this.#later()
  }

  markMeta() {
    this.#metaDirty = true
    this.#later()
  }

  #later() {
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => void this.flush(), DELAY_MS)
  }

  /** Whether a page has changes that are not on disk yet. */
  pending(id: string) {
    return this.#dirty.has(id)
  }

  /** Takes the copy now and resolves when it is on disk (writes run one after the other). */
  flush(): Promise<void> {
    clearTimeout(this.#timer)
    if (!this.#dirty.size && !this.#metaDirty) return this.#chain
    const ids = [...this.#dirty]
    const withMeta = this.#metaDirty
    this.#dirty.clear()
    this.#metaDirty = false

    const writes: PageWrite[] = []
    const remove: string[] = []
    for (const id of ids) {
      const p = this.#src.page(id)
      if (!p) remove.push(id)
      else {
        const { content, ...meta } = p
        writes.push({ meta: plain(meta) as StoredPage, body: content ? plain(content) : null })
      }
    }
    const meta = withMeta ? plain({ tags: this.#src.tags, settings: this.#src.settings }) : undefined

    this.#chain = this.#chain.then(async () => {
      try {
        await this.store.write(writes, remove, meta)
        this.#failed = false
      } catch (e) {
        // keep the changes for the next try
        for (const id of ids) this.#dirty.add(id)
        if (withMeta) this.#metaDirty = true
        if (!this.#failed) this.onerror(e)
        this.#failed = true
      }
    })
    return this.#chain
  }

  /** Writes what is left and lets go of the database. */
  async close() {
    document.removeEventListener('visibilitychange', this.#leave)
    window.removeEventListener('pagehide', this.#hide)
    await this.flush()
    this.store.close()
  }
}
