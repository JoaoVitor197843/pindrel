import { deleteDB, openDB, type DBSchema, type IDBPDatabase, type IDBPTransaction } from 'idb'
import type { Block } from '../stores/blocks'
import type { NotePage, Settings, Tag } from '../stores/workspace.svelte'

// One object store per kind of item, so each can later get its own treatment (the vault its encryption, the media its
// quota) without touching the others:
//   pages    metadata of every page (what the dashboard needs; never a body)
//   bodies   the blocks of a page, read only when the page is opened
//   secrets  everything that must not sit next to ordinary text: the text of `secure` blocks and the whole body of a
//            vault page. Plain for now; the vault's key arrives with the vault itself.
//   media    pictures, as Blobs (never base64: no 33% overhead, no string in memory)
//   meta     tags and settings
interface Schema extends DBSchema {
  pages: { key: string; value: StoredPage }
  bodies: { key: string; value: { id: string; blocks: Block[] } }
  secrets: { key: string; value: Secret; indexes: { pageId: string } }
  media: { key: string; value: Media; indexes: { pageId: string } }
  meta: { key: string; value: unknown }
}

export type StoredPage = Omit<NotePage, 'content'>

type Secret = { key: string; pageId: string } & ({ kind: 'block'; text: string } | { kind: 'page'; blocks: Block[]; excerpt: string })

export interface Media {
  id: string
  pageId: string
  name: string
  type: string
  size: number
  blob: Blob
}

export interface PageWrite {
  meta: StoredPage
  /** null: the body was never loaded in this session, so what is on disk stays as it is. */
  body: Block[] | null
}

export interface Loaded {
  pages: StoredPage[]
  tags: Tag[] | null
  settings: Settings | null
}

/** The notes of the "no login" mode: they live in this browser only and never sync. */
export const LOCAL_DB = 'pindrel-local'
/** What the local database was called before the modes were told apart. */
const LEGACY_DB = 'pindrel-notes'
const VERSION = 1
/** One database per account, so two people on the same browser never see each other's notes. */
export const cloudDbName = (accountId: string) => {
  // the id comes from the server: it only ever becomes a database name when it looks like one
  if (!/^[0-9a-fA-F-]{8,64}$/.test(accountId)) throw new Error('invalid account id')
  return `pindrel-cloud-${accountId.toLowerCase()}`
}
const STORES = ['pages', 'bodies', 'secrets', 'media', 'meta'] as const
const COPY_BATCH = 50

const blockKey = (pageId: string, blockId: string) => `b:${pageId}:${blockId}`
const pageKey = (pageId: string) => `p:${pageId}`

type Tx = IDBPTransaction<Schema, ['pages', 'bodies', 'secrets', 'media', 'meta'], 'readwrite'>

export class NotesStore {
  #db: IDBPDatabase<Schema>

  private constructor(db: IDBPDatabase<Schema>) {
    this.#db = db
  }

  static async open(name = LOCAL_DB): Promise<NotesStore> {
    const db = await openDB<Schema>(name, VERSION, {
      upgrade(db) {
        db.createObjectStore('pages', { keyPath: 'id' })
        db.createObjectStore('bodies', { keyPath: 'id' })
        db.createObjectStore('secrets', { keyPath: 'key' }).createIndex('pageId', 'pageId')
        db.createObjectStore('media', { keyPath: 'id' }).createIndex('pageId', 'pageId')
        db.createObjectStore('meta')
      },
      // another tab asked for a newer schema: let it, this one reopens on its next load
      blocking() {
        db.close()
      },
    })
    return new NotesStore(db)
  }

  /** The database of one account. */
  static openAccount(accountId: string): Promise<NotesStore> {
    return NotesStore.open(cloudDbName(accountId))
  }

  /** The local database; first brings in whatever the old name held, once. */
  static async openLocal(): Promise<NotesStore> {
    await moveLegacy(LOCAL_DB, LEGACY_DB)
    return NotesStore.open(LOCAL_DB)
  }

  close() {
    this.#db.close()
  }

  async loadAll(): Promise<Loaded> {
    const tx = this.#db.transaction(['pages', 'meta'])
    const [pages, tags, settings] = await Promise.all([tx.objectStore('pages').getAll(), tx.objectStore('meta').get('tags'), tx.objectStore('meta').get('settings')])
    return { pages, tags: (tags as Tag[] | undefined) ?? null, settings: (settings as Settings | undefined) ?? null }
  }

  /** The blocks of a page, with the text of its secure blocks put back; null when nothing is stored for it. */
  async loadBody(id: string): Promise<Block[] | null> {
    const tx = this.#db.transaction(['bodies', 'secrets'])
    const secrets = await tx.objectStore('secrets').index('pageId').getAll(id)
    const whole = secrets.find((s) => s.kind === 'page')
    if (whole && whole.kind === 'page') return whole.blocks
    const body = await tx.objectStore('bodies').get(id)
    if (!body) return null
    const texts = new Map(secrets.flatMap((s) => (s.kind === 'block' ? [[s.key, s.text] as const] : [])))
    return body.blocks.map((b) => (b.type === 'secure' ? { ...b, text: texts.get(blockKey(id, b.id)) ?? '' } : b))
  }

  /** The excerpts of vault pages, which are kept with their bodies and not in the list. */
  async loadVaultExcerpts(): Promise<Map<string, string>> {
    const all = await this.#db.getAll('secrets')
    return new Map(all.flatMap((s) => (s.kind === 'page' ? [[s.pageId, s.excerpt] as const] : [])))
  }

  /** Everything in one transaction: either the whole batch is on disk or none of it. */
  async write(pages: PageWrite[], remove: string[], meta?: { tags: Tag[]; settings: Settings }): Promise<void> {
    const tx = this.#db.transaction(['pages', 'bodies', 'secrets', 'media', 'meta'], 'readwrite')
    const work: Promise<unknown>[] = []

    for (const id of remove) {
      work.push(tx.objectStore('pages').delete(id), tx.objectStore('bodies').delete(id))
      work.push(this.#deleteByPage(tx, 'secrets', id), this.#deleteByPage(tx, 'media', id))
    }

    for (const { meta: page, body } of pages) {
      // a vault page keeps no text in the list either
      work.push(tx.objectStore('pages').put(page.locked ? { ...page, excerpt: '' } : page))
      if (!body) continue
      work.push(this.#deleteByPage(tx, 'secrets', page.id).then(() => this.#putBody(tx, page, body)))
    }

    if (meta) {
      work.push(tx.objectStore('meta').put(meta.tags, 'tags'), tx.objectStore('meta').put(meta.settings, 'settings'))
    }
    await Promise.all([...work, tx.done])
  }

  async #deleteByPage(tx: Tx, name: 'secrets' | 'media', pageId: string) {
    const store = tx.objectStore(name)
    for (const key of await store.index('pageId').getAllKeys(pageId)) await store.delete(key)
  }

  async #putBody(tx: Tx, page: StoredPage, body: Block[]) {
    const bodies = tx.objectStore('bodies')
    const secrets = tx.objectStore('secrets')
    if (page.locked) {
      await bodies.delete(page.id)
      await secrets.put({ key: pageKey(page.id), pageId: page.id, kind: 'page', blocks: body, excerpt: page.excerpt })
      return
    }
    const blocks: Block[] = []
    for (const b of body) {
      if (b.type === 'secure') {
        await secrets.put({ key: blockKey(page.id, b.id), pageId: page.id, kind: 'block', text: b.text })
        blocks.push({ ...b, text: '' })
      } else blocks.push(b)
    }
    await bodies.put({ id: page.id, blocks })
  }

  /** Keeps a picture in its own store and returns the id the block points at. */
  async putMedia(pageId: string, file: Blob & { name?: string }): Promise<string> {
    const id = `m${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`
    await this.#db.put('media', { id, pageId, name: file.name ?? '', type: file.type, size: file.size, blob: file })
    return id
  }

  async getMedia(id: string): Promise<Blob | null> {
    return (await this.#db.get('media', id))?.blob ?? null
  }

  async deleteMedia(id: string): Promise<void> {
    await this.#db.delete('media', id)
  }

  /** Bytes the pictures take, for the storage line of the settings. */
  async mediaBytes(): Promise<number> {
    let total = 0
    const tx = this.#db.transaction('media')
    for (let c = await tx.store.openCursor(); c; c = await c.continue()) total += c.value.size
    return total
  }
}

/**
 * IndexedDB cannot rename a database, so the old one is copied into the new name and then deleted. It goes a batch at a
 * time (bodies and pictures can be large), and putting a record twice is harmless, so a copy that was cut short just
 * runs again at the next start, before anything else can write.
 */
export async function moveLegacy(to: string, from: string): Promise<void> {
  // without databases() there is no way to ask without creating the old database empty: leave it alone
  const known = await indexedDB.databases?.()
  if (!known?.some((d) => d.name === from)) return
  const old = await openDB(from)
  try {
    // not shaped like ours: nothing to copy, and it is not ours to delete
    if (!STORES.every((n) => old.objectStoreNames.contains(n))) return
    const target = await NotesStore.open(to)
    target.close()
    const dest = await openDB(to)
    try {
      for (const name of STORES) {
        let after: IDBValidKey | undefined
        for (;;) {
          const range = after === undefined ? undefined : IDBKeyRange.lowerBound(after, true)
          const keys = await old.getAllKeys(name, range, COPY_BATCH)
          if (!keys.length) break
          const values = await Promise.all(keys.map((k) => old.get(name, k)))
          const tx = dest.transaction(name, 'readwrite')
          const inline = tx.store.keyPath !== null
          await Promise.all([...keys.map((k, i) => (inline ? tx.store.put(values[i]) : tx.store.put(values[i], k))), tx.done])
          after = keys[keys.length - 1]
        }
      }
    } finally {
      dest.close()
    }
  } finally {
    old.close()
  }
  await deleteDB(from)
}
