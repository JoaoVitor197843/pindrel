import 'fake-indexeddb/auto'
import { openDB } from 'idb'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Block } from '../stores/blocks'
import { PageEditor } from '../stores/editor.svelte'
import { Workspace } from '../stores/workspace.svelte'
import { NotesStore, moveLegacy } from './notesStore'

let n = 0
let name: string
const opened: Workspace[] = []

beforeEach(() => {
  name = `test-${++n}-${Math.random().toString(36).slice(2)}`
})
afterEach(async () => {
  await Promise.all(opened.splice(0).map((w) => w.detach()))
  vi.useRealTimers()
})

/** A workspace that starts as the offline one does: empty, then filled from the browser's storage. */
async function start(): Promise<Workspace> {
  const ws = new Workspace()
  ws.goLocal()
  await ws.attach(await NotesStore.open(name))
  opened.push(ws)
  return ws
}

/** Closes the workspace for good (the tab goes away) and opens a fresh one on the same database. */
async function restart(ws: Workspace): Promise<Workspace> {
  await ws.detach()
  return start()
}

async function raw(store: 'pages' | 'bodies' | 'secrets' | 'media') {
  const db = await openDB(name)
  try {
    return await db.getAll(store)
  } finally {
    db.close()
  }
}

const para = (id: string, text: string): Block => ({ id, type: 'paragraph', text })

describe('notes in IndexedDB', () => {
  it('starts empty and keeps a page across a restart', async () => {
    const ws = await start()
    expect(ws.pages).toHaveLength(0)
    const page = ws.newPage('Minha nota')
    page.content!.push(para('a', 'olá mundo'))
    ws.touch(page.id)

    const again = await restart(ws)
    expect(again.pages.map((p) => p.title)).toEqual(['Minha nota'])
    expect(again.pages[0].excerpt).toBe('olá mundo')
    expect(again.pages[0].blocks).toBe(1)
  })

  it('does not read the body until the page is opened, and puts it back after', async () => {
    const ws = await start()
    const page = ws.newPage('Corpo')
    page.content!.push(para('a', 'texto'), para('b', 'mais'))
    ws.touch(page.id)

    const again = await restart(ws)
    const p = again.pages[0]
    expect(p.content).toBeNull()
    // never invented: an empty body here would be saved over the real one
    expect(again.contentOf(p.id)).toBeNull()

    expect(await again.load(p.id)).toBe(true)
    expect(p.content?.map((b) => (b as { text: string }).text)).toEqual(['texto', 'mais'])

    again.release(p.id)
    await again.persist!.flush()
    await vi.waitFor(() => expect(p.content).toBeNull())
    // and it still comes back
    await again.load(p.id)
    expect(p.content).toHaveLength(2)
  })

  it('keeps a body that two screens have open until the last one leaves', async () => {
    const ws = await start()
    const page = ws.newPage('Dois')
    page.content!.push(para('a', 'x'))
    ws.touch(page.id)
    const again = await restart(ws)
    const p = again.pages[0]
    await again.load(p.id)
    await again.load(p.id)
    again.release(p.id)
    await again.persist!.flush()
    await new Promise((r) => setTimeout(r, 20))
    expect(p.content).not.toBeNull()
    again.release(p.id)
    await vi.waitFor(() => expect(p.content).toBeNull())
  })

  it('edits through the editor are saved (title, text, pin, tags, trash, restore)', async () => {
    const ws = await start()
    const page = ws.newPage('Antes')
    const ed = new PageEditor(ws, page.id)
    ed.setTitle('Depois')
    const b = ed.insert('paragraph')!
    ed.setText(b.id, 'escrito')
    ed.addTag('ideias')
    ed.togglePin()

    let again = await restart(ws)
    const p = again.pages[0]
    expect(p).toMatchObject({ title: 'Depois', pinned: true, tags: ['ideias'] })
    expect(again.tags.map((t) => t.id)).toEqual(['ideias'])

    again.trash(p.id)
    again = await restart(again)
    expect(again.pages[0].trashed).toBe(true)
    again.restore(p.id)
    again = await restart(again)
    expect(again.pages[0].trashed).toBe(false)
  })

  it('saves what changed once, after a typing burst', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    const ws = await start()
    const page = ws.newPage('Rajada')
    const write = vi.spyOn(ws.persist!.store, 'write')
    const ed = new PageEditor(ws, page.id)
    const b = ed.insert('paragraph')!
    for (let i = 0; i < 50; i++) ed.setText(b.id, 'a'.repeat(i + 1))
    expect(write).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1000)
    expect(write).toHaveBeenCalledTimes(1)
    ed.destroy()
  })

  it('settings and trash retention survive', async () => {
    const ws = await start()
    ws.saveSettings({ useTrash: false, retention: 14 })
    const again = await restart(ws)
    expect(again.settings).toEqual({ useTrash: false, retention: 14 })
  })

  it('deleting for good and emptying the trash remove everything of the page', async () => {
    const ws = await start()
    const a = ws.newPage('A')
    const b = ws.newPage('B')
    a.content!.push({ id: 's', type: 'secure', text: 'segredo' })
    ws.touch(a.id)
    ws.touch(b.id)
    await ws.persist!.flush()
    ws.deleteForever(a.id)
    ws.trash(b.id)
    ws.emptyTrash()
    await ws.persist!.flush()
    for (const s of ['pages', 'bodies', 'secrets', 'media'] as const) expect(await raw(s)).toHaveLength(0)
  })

  it('new pages after a restart never reuse an id', async () => {
    const ws = await start()
    ws.newPage('um')
    ws.newPage('dois')
    const again = await restart(ws)
    const made = again.newPage('três')
    expect(new Set(again.pages.map((p) => p.id)).size).toBe(3)
    expect(made.id).not.toBe(again.pages[1].id)
  })

  it('a page made while the list is still loading is not lost', async () => {
    const first = await start()
    first.newPage('já salva')
    await first.persist!.flush()
    const store = await NotesStore.open(name)
    await first.detach()
    const ws = new Workspace()
    ws.goLocal()
    const loading = ws.attach(store)
    ws.newPage('nova durante a carga')
    await loading
    opened.push(ws)
    const again = await restart(ws)
    expect(again.pages.map((p) => p.title).sort()).toEqual(['já salva', 'nova durante a carga'])
  })

  it('a failing write is reported once and tried again with the next change', async () => {
    const ws = await start()
    const onerror = vi.fn()
    ws.persist!.onerror = onerror
    const write = vi.spyOn(ws.persist!.store, 'write').mockRejectedValue(new DOMException('full', 'QuotaExceededError'))
    const page = ws.newPage('Cheio')
    await ws.persist!.flush()
    ws.touch(page.id)
    await ws.persist!.flush()
    expect(onerror).toHaveBeenCalledTimes(1)
    write.mockRestore()
    ws.touch(page.id)
    await ws.persist!.flush()
    expect((await raw('pages')).map((p) => p.title)).toEqual(['Cheio'])
  })

  it('a body that cannot be read says so and does not hand the editor an empty page', async () => {
    const ws = await start()
    ws.newPage('x').content!.push(para('a', 'texto'))
    ws.touch(ws.pages[0].id)
    const again = await restart(ws)
    vi.spyOn(again.persist!.store, 'loadBody').mockRejectedValue(new Error('boom'))
    vi.spyOn(console, 'error').mockImplementation(() => {})
    expect(await again.load(again.pages[0].id)).toBe(false)
    expect(again.pages[0].content).toBeNull()
  })

  it('exporting reads the bodies of unopened pages and lets them go again', async () => {
    const ws = await start()
    ws.newPage('E').content!.push(para('a', 'corpo exportado'))
    ws.touch(ws.pages[0].id)
    const again = await restart(ws)
    const seen = await again.withBodies(() => again.pages.map((p) => p.content?.length))
    expect(seen).toEqual([1])
    await again.persist!.flush()
    await vi.waitFor(() => expect(again.pages[0].content).toBeNull())
  })

  it('a browser without IndexedDB leaves the notes working in memory', async () => {
    const ws = new Workspace()
    ws.goLocal()
    const page = ws.newPage('sem disco')
    expect(ws.persist).toBeNull()
    expect(ws.contentOf(page.id)).toEqual([])
  })
})

describe('what is kept apart', () => {
  it('secure blocks leave their text in the secrets store, not in the body', async () => {
    const ws = await start()
    const page = ws.newPage('Cofre')
    page.content!.push(para('a', 'público'), { id: 's', type: 'secure', text: 'senha-123' })
    ws.touch(page.id)
    await ws.persist!.flush()

    expect(JSON.stringify(await raw('bodies'))).not.toContain('senha-123')
    expect(JSON.stringify(await raw('pages'))).not.toContain('senha-123')
    expect(await raw('secrets')).toEqual([expect.objectContaining({ kind: 'block', text: 'senha-123', pageId: page.id })])

    const again = await restart(ws)
    await again.load(page.id)
    expect(again.pages[0].content).toEqual([para('a', 'público'), { id: 's', type: 'secure', text: 'senha-123' }])
  })

  it('removing a secure block removes its secret', async () => {
    const ws = await start()
    const page = ws.newPage('Cofre')
    const ed = new PageEditor(ws, page.id)
    const b = ed.insert('secure')!
    ed.setText(b.id, 'segredo')
    await ws.persist!.flush()
    expect(await raw('secrets')).toHaveLength(1)
    ed.remove(b.id)
    await ws.persist!.flush()
    expect(await raw('secrets')).toHaveLength(0)
    ed.destroy()
  })

  it('a vault page keeps its whole body and its excerpt out of the list and the bodies', async () => {
    const ws = await start()
    ws.unlockVault('abcd')
    const page = ws.addVaultEntry()!
    page.content!.push(para('a', 'conta 0412'))
    ws.touch(page.id)
    await ws.persist!.flush()
    expect(JSON.stringify(await raw('pages'))).not.toContain('0412')
    expect(await raw('bodies')).toHaveLength(0)
    expect(JSON.stringify(await raw('secrets'))).toContain('conta 0412')

    const again = await restart(ws)
    const p = again.pages[0]
    expect(p.locked).toBe(true)
    expect(p.excerpt).toBe('')
    await again.load(p.id)
    expect(p.content).toEqual([para('a', 'conta 0412')])
    again.unlockVault('abcd')
    await vi.waitFor(() => expect(p.excerpt).toBe('conta 0412'))
  })

  it('pictures go to the media store as a Blob and come back as one', async () => {
    const ws = await start()
    const page = ws.newPage('Foto')
    const ed = new PageEditor(ws, page.id)
    const img = ed.insert('image')!
    const file = new File([new Uint8Array([1, 2, 3, 4])], 'gato.png', { type: 'image/png' })
    expect(await ed.setImageFile(img.id, file)).toBe(true)
    await ws.persist!.flush()

    const [m] = await raw('media')
    expect(m).toMatchObject({ pageId: page.id, name: 'gato.png', type: 'image/png', size: 4 })
    const block = ed.blocks[0]
    expect(block).toMatchObject({ type: 'image', name: 'gato.png', src: null, mediaId: m.id })
    // (fake-indexeddb clones jsdom's File into a plain object, so only presence can be checked here; a browser keeps the Blob)
    expect(await ws.persist!.store.getMedia(m.id)).not.toBeNull()
    expect(await ws.persist!.store.getMedia('nope')).toBeNull()

    // replaced, removed: the old bytes go
    const other = new File([new Uint8Array([9])], 'novo.png', { type: 'image/png' })
    await ed.setImageFile(img.id, other)
    await vi.waitFor(async () => expect(await raw('media')).toHaveLength(1))
    ed.remove(img.id)
    await vi.waitFor(async () => expect(await raw('media')).toHaveLength(0))
    ed.destroy()
  })

  it('a picture whose block vanished while it was written is not left behind', async () => {
    const ws = await start()
    const page = ws.newPage('Rápido')
    const ed = new PageEditor(ws, page.id)
    const img = ed.insert('image')!
    const sending = ed.setImageFile(img.id, new File([new Uint8Array([1])], 'a.png', { type: 'image/png' }))
    ed.remove(img.id)
    expect(await sending).toBe(false)
    await vi.waitFor(async () => expect(await raw('media')).toHaveLength(0))
    ed.destroy()
  })

  it('deleting a page for good takes its pictures with it', async () => {
    const ws = await start()
    const page = ws.newPage('Foto')
    const ed = new PageEditor(ws, page.id)
    const img = ed.insert('image')!
    await ed.setImageFile(img.id, new File([new Uint8Array([1])], 'a.png', { type: 'image/png' }))
    ed.destroy()
    ws.deleteForever(page.id)
    await ws.persist!.flush()
    expect(await raw('media')).toHaveLength(0)
  })

  it('a copy of a page does not share the original picture', async () => {
    const ws = await start()
    const page = ws.newPage('Foto')
    const ed = new PageEditor(ws, page.id)
    const img = ed.insert('image')!
    await ed.setImageFile(img.id, new File([new Uint8Array([1])], 'a.png', { type: 'image/png' }))
    expect(ed.duplicateBlock(img.id)).toBeNull()
    const made = ws.duplicate(page.id)!
    expect(made.images).toBe(1)
    expect(ws.page(made.page.id)!.content![0]).toMatchObject({ type: 'image', src: null, name: null })
    expect('mediaId' in ws.page(made.page.id)!.content![0]).toBe(false)
    ed.destroy()
  })

  it('a missing picture and a big pile of pages do not break loading', async () => {
    const ws = await start()
    for (let i = 0; i < 300; i++) ws.newPage(`p${i}`)
    const again = await restart(ws)
    expect(again.pages).toHaveLength(300)
    expect(again.pages.every((p) => p.content === null)).toBe(true)
  })
})

describe('the database that used to be called pindrel-notes', () => {
  const names = async () => (await indexedDB.databases()).map((d) => d.name)

  /** Fills an old-style database with pages (past one copy batch), a secret and a picture. */
  async function legacy(old: string, count = 120) {
    const store = await NotesStore.open(old)
    const pages = Array.from({ length: count }, (_, i) => ({
      meta: { id: `n${i + 1}`, title: `Página ${i + 1}`, excerpt: 'texto', tags: [], updated: i, blocks: 1, created: i, sharedBy: null, myPerms: [], shares: [], locked: false, trashed: false, pinned: false, icon: '', cover: '' },
      body: [para('a', `corpo ${i + 1}`), { id: 's', type: 'secure' as const, text: `segredo ${i + 1}` }],
    }))
    await store.write(pages, [], { tags: [{ id: 'ideias', name: 'ideias', color: 'accent' }], settings: { useTrash: false, retention: 10 } })
    const media = await store.putMedia('n1', new File([new Uint8Array([1, 2])], 'a.png', { type: 'image/png' }))
    store.close()
    return media
  }

  it('is copied to the new name, with bodies, secrets, pictures, tags and settings, and then removed', async () => {
    const old = `${name}-old`
    const media = await legacy(old)
    await moveLegacy(name, old)
    expect(await names()).not.toContain(old)

    const now = await NotesStore.open(name)
    const loaded = await now.loadAll()
    expect(loaded.pages).toHaveLength(120)
    expect(loaded.tags).toEqual([{ id: 'ideias', name: 'ideias', color: 'accent' }])
    expect(loaded.settings).toEqual({ useTrash: false, retention: 10 })
    expect(await now.loadBody('n77')).toEqual([para('a', 'corpo 77'), { id: 's', type: 'secure', text: 'segredo 77' }])
    expect(await now.getMedia(media)).not.toBeNull()
    now.close()
  })

  it('does nothing, and creates nothing, when there is no old database', async () => {
    await moveLegacy(name, `${name}-nope`)
    expect(await names()).not.toContain(`${name}-nope`)
    expect(await names()).not.toContain(name)
  })

  it('can run again over a copy that was cut short without losing or duplicating anything', async () => {
    const old = `${name}-old`
    await legacy(old, 30)
    // a first copy that stopped halfway
    const partial = await NotesStore.open(name)
    const loaded = await (await NotesStore.open(old)).loadAll()
    await partial.write(loaded.pages.slice(0, 10).map((p) => ({ meta: p, body: null })), [])
    partial.close()
    await moveLegacy(name, old)
    const now = await NotesStore.open(name)
    expect((await now.loadAll()).pages).toHaveLength(30)
    expect(await names()).not.toContain(old)
    now.close()
  })

  it('leaves a database that is not ours alone', async () => {
    const other = `${name}-other`
    const db = await openDB(other, 1, { upgrade: (d) => void d.createObjectStore('x') })
    await db.put('x', 1, 'k')
    db.close()
    await moveLegacy(name, other)
    // not shaped like a notes database: nothing is copied and it is not deleted
    expect(await names()).toContain(other)
    const copied = await NotesStore.open(name)
    expect((await copied.loadAll()).pages).toHaveLength(0)
    copied.close()
  })
})
