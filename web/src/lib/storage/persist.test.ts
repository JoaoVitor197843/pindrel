import 'fake-indexeddb/auto'
import { sampleWorkspace } from '../sample'
import { openDB } from 'idb'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Block } from '../stores/blocks'
import { PageEditor } from '../stores/editor.svelte'
import { Workspace } from '../stores/workspace.svelte'
import { NotesStore, cloudDbName, moveLegacy } from './notesStore'

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
  const ws = sampleWorkspace()
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

  it('two tabs on the same database never give two new pages the same id', async () => {
    // nothing tells one tab what the other wrote: the old counter, raised only when the list loaded, made the second
    // tab reuse the first tab's id and its page replaced the other one on disk
    const a = await start()
    const b = await start()
    const one = a.newPage('Da aba A')
    a.touch(one.id)
    await a.persist!.flush()
    const two = b.newPage('Da aba B')
    b.touch(two.id)
    await b.persist!.flush()
    expect(two.id).not.toBe(one.id)
    expect((await raw('pages')).map((p) => p.title).sort()).toEqual(['Da aba A', 'Da aba B'])
  })

  it('a newer Pindrel opening the database in another tab gets what this tab had not written yet', async () => {
    const ws = await start()
    const page = ws.newPage('Escrita antes da atualização')
    ws.touch(page.id) // still waiting for the 400 ms of the debounce
    // the other tab, with a newer schema: its open waits until this tab lets go
    const newer = await openDB(name, 99)
    try {
      const titles = (await newer.getAll('pages')).map((p: { title: string }) => p.title)
      expect(titles).toContain('Escrita antes da atualização')
    } finally {
      newer.close()
    }
    expect(ws.persist!.store.upgradedElsewhere).toBe(true)
  })

  it('a page made while the list is still loading is not lost', async () => {
    const first = await start()
    first.newPage('já salva')
    await first.persist!.flush()
    const store = await NotesStore.open(name)
    await first.detach()
    const ws = sampleWorkspace()
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

  it('an export with a body that cannot be read is not made, and the bodies that were read go again', async () => {
    // before: the page went out as its excerpt (Markdown) or as nothing (JSON), under "Exportação pronta"
    const ws = await start()
    ws.newPage('Legível').content!.push(para('a', 'um'))
    ws.newPage('Ilegível').content!.push(para('b', 'dois'))
    for (const p of ws.pages) ws.touch(p.id)
    const again = await restart(ws)
    const broken = again.pages.find((p) => p.title === 'Ilegível')!.id
    const real = again.persist!.store.loadBody.bind(again.persist!.store)
    vi.spyOn(again.persist!.store, 'loadBody').mockImplementation((id: string) => (id === broken ? Promise.reject(new Error('boom')) : real(id)))
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const made = vi.fn(() => 'arquivo')
    expect(await again.withBodies(made)).toBeNull()
    expect(made).not.toHaveBeenCalled()
    await again.persist!.flush()
    await vi.waitFor(() => expect(again.pages.every((p) => p.content === null)).toBe(true))
  })

  it('a browser without IndexedDB leaves the notes working in memory', async () => {
    const ws = sampleWorkspace()
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

  it('the excerpts of the vault come from the page records only, never from a read of every secret', async () => {
    const ws = await start()
    ws.unlockVault('abcd')
    for (const text of ['primeira 01', 'segunda 02']) {
      const page = ws.addVaultEntry()!
      page.content!.push(para('a', text))
      ws.touch(page.id)
    }
    const normal = ws.newPage('Comum')
    normal.content!.push({ id: 's', type: 'secure', text: 'segredo de bloco' } as Block)
    ws.touch(normal.id)
    await ws.persist!.flush()
    const store = await NotesStore.open(name)
    try {
      const all = vi.spyOn(IDBObjectStore.prototype, 'getAll')
      const excerpts = await store.loadVaultExcerpts()
      expect([...excerpts.values()].sort()).toEqual(['primeira 01', 'segunda 02'])
      expect(all).not.toHaveBeenCalled()
      all.mockRestore()
    } finally {
      store.close()
    }
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

describe('the trash empties itself', () => {
  const DAY = 86_400_000

  it('a page left in the trash longer than the retention is deleted for good at the next start', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date(2026, 0, 1))
    const ws = await start()
    const old = ws.newPage('velha')
    const recent = ws.newPage('recente')
    ws.trash(old.id)
    vi.setSystemTime(new Date(2026, 0, 25))
    ws.trash(recent.id)
    vi.setSystemTime(new Date(2026, 1, 5)) // 35 days after the first went to the trash, 11 after the second
    const again = await restart(ws)
    expect(again.pages.map((p) => p.title)).toEqual(['recente'])
    await again.persist!.flush()
    expect((await raw('pages')).map((p) => p.title)).toEqual(['recente'])
  })

  it('counts from the day it went to the trash, not from the last edit', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date(2026, 0, 1))
    const ws = await start()
    const p = ws.newPage('editada há muito tempo')
    await ws.persist!.flush()
    vi.setSystemTime(new Date(2026, 2, 1))
    ws.trash(p.id)
    vi.setSystemTime(new Date(2026, 2, 2))
    expect((await restart(ws)).pages).toHaveLength(1)
  })

  it('a page already in the trash before the date was kept gets the whole retention from now on', async () => {
    const ws = await start()
    const p = ws.newPage('antiga')
    p.trashed = true
    p.updated = Date.now() - 400 * DAY
    ws.touch(p.id)
    p.updated = Date.now() - 400 * DAY
    await ws.persist!.flush()
    const again = await restart(ws)
    expect(again.pages).toHaveLength(1)
    expect(again.pages[0].trashedAt).toBeGreaterThan(Date.now() - DAY)
  })

  it('a shorter retention saved in the settings applies at once; restoring a page stops the count', async () => {
    const ws = await start()
    const a = ws.newPage('a')
    const b = ws.newPage('b')
    ws.trash(a.id)
    ws.trash(b.id)
    ws.restore(b.id)
    ws.page(a.id)!.trashedAt = Date.now() - 10 * DAY
    ws.page(b.id)!.updated = Date.now() - 10 * DAY
    ws.saveSettings({ useTrash: true, retention: 7 })
    expect(ws.pages.map((p) => p.title)).toEqual(['b'])
    expect(ws.page(b.id)!.trashedAt).toBeUndefined()
  })
})

describe('files on the server and pages whose body is only on disk', () => {
  const file = (fileId: string): Block => ({ id: `blk-${fileId}`, type: 'file', fileId, name: fileId, size: 1, mime: '', level: 3 })

  /** A workspace where `a` and its copy `b` share the file `f1`, and `a` alone has `f2`; both bodies went back to disk. */
  async function shared() {
    const ws = await start()
    const gone: string[][] = []
    ws.filesGone = (ids) => gone.push(ids)
    const a = ws.newPage('a')
    a.content!.push(file('f1'), file('f2'))
    ws.touch(a.id)
    const b = ws.newPage('b')
    b.content!.push(file('f1'))
    ws.touch(b.id)
    const again = await restart(ws)
    again.filesGone = (ids) => gone.push(ids)
    expect(again.pages.every((p) => p.content === null)).toBe(true)
    return { ws: again, gone, a: again.pages.find((p) => p.title === 'a')!.id, b: again.pages.find((p) => p.title === 'b')!.id }
  }

  it('deleting a page that was never opened still lets its files go, and keeps the ones another closed page uses', async () => {
    const { ws, gone, a } = await shared()
    await ws.deleteForever(a)
    expect(gone).toEqual([['f2']])
  })

  it('emptying the trash reads the bodies of the pages that leave', async () => {
    const { ws, gone, a, b } = await shared()
    ws.trash(a)
    ws.trash(b)
    await ws.emptyTrash()
    expect(gone.flat().sort()).toEqual(['f1', 'f2'])
  })

  it('removing a block does not mark as unused a file that a closed copy of the page still shows', async () => {
    const { ws, a } = await shared()
    await ws.load(a)
    const orphaned: string[] = []
    const ed = new PageEditor(ws, a)
    ed.files = { ...ed.files, orphan: (id: string, on: boolean) => on && orphaned.push(id) } as typeof ed.files
    ed.remove('blk-f1')
    ed.remove('blk-f2')
    await vi.waitFor(() => expect(orphaned).toEqual(['f2']))
    await new Promise((r) => setTimeout(r, 20))
    expect(orphaned).toEqual(['f2'])
    ed.destroy()
  })

  it('asking whether a file is still used walks no body: it is one index lookup per file', async () => {
    const { ws } = await shared()
    for (let i = 0; i < 30; i++) ws.newPage(`outra ${i}`).content!.push(file(`x${i}`))
    const again = await restart(ws)
    const cursors = vi.spyOn(IDBObjectStore.prototype, 'openCursor')
    const all = vi.spyOn(IDBObjectStore.prototype, 'getAll')
    expect([...(await again.filesInUse(['f1', 'x7', 'nada']))].sort()).toEqual(['f1', 'x7'])
    expect(cursors).not.toHaveBeenCalled()
    expect(all).not.toHaveBeenCalled()
    cursors.mockRestore()
    all.mockRestore()
  })

  it('a closed vault page still holds on to its files', async () => {
    const ws = await start()
    const gone: string[][] = []
    const a = ws.newPage('a')
    a.content!.push(file('f9'))
    const cofre = ws.newPage('cofre')
    cofre.content!.push(file('f9'))
    cofre.locked = true
    ws.touch(a.id)
    ws.touch(cofre.id)
    const again = await restart(ws)
    again.filesGone = (ids) => gone.push(ids)
    expect([...(await again.filesInUse(['f9']))]).toEqual(['f9'])
    await again.deleteForever(again.pages.find((p) => p.title === 'a')!.id)
    expect(gone).toEqual([])
  })

  it('a database from before the file index finds the files of its bodies after the upgrade', async () => {
    const db = await openDB(name, 1, {
      upgrade(d) {
        d.createObjectStore('pages', { keyPath: 'id' })
        d.createObjectStore('bodies', { keyPath: 'id' })
        d.createObjectStore('secrets', { keyPath: 'key' }).createIndex('pageId', 'pageId')
        d.createObjectStore('media', { keyPath: 'id' }).createIndex('pageId', 'pageId')
        d.createObjectStore('meta')
      },
    })
    const meta = (id: string, locked = false) => ({ id, title: id, excerpt: '', tags: [], updated: 1, blocks: 1, created: 1, sharedBy: null, myPerms: [], shares: [], locked, trashed: false, pinned: false, icon: '', cover: '' })
    await db.put('pages', meta('velha'))
    await db.put('bodies', { id: 'velha', blocks: [file('f1')] })
    await db.put('pages', meta('cofre', true))
    await db.put('secrets', { key: 'p:cofre', pageId: 'cofre', kind: 'page', blocks: [file('f2')], excerpt: '' })
    await db.put('secrets', { key: 'b:velha:s', pageId: 'velha', kind: 'block', text: 'segredo' })
    db.close()
    const ws = await start()
    expect([...(await ws.filesInUse(['f1', 'f2', 'f3']))].sort()).toEqual(['f1', 'f2'])
    expect(await ws.persist!.store.loadBody('velha')).toEqual([file('f1')])
  })

  it('a body copied from the old database name is found by its files too', async () => {
    const old = `${name}-old`
    const db = await openDB(old, 1, {
      upgrade(d) {
        for (const s of ['pages', 'bodies', 'media']) d.createObjectStore(s, { keyPath: 'id' })
        d.createObjectStore('secrets', { keyPath: 'key' }).createIndex('pageId', 'pageId')
        d.createObjectStore('meta')
      },
    })
    await db.put('pages', { id: 'n1', title: 'n1', excerpt: '', tags: [], updated: 1, blocks: 1, created: 1, sharedBy: null, myPerms: [], shares: [], locked: false, trashed: false, pinned: false, icon: '', cover: '' })
    await db.put('bodies', { id: 'n1', blocks: [file('f5')] })
    db.close()
    await moveLegacy(name, old)
    const ws = await start()
    expect([...(await ws.filesInUse(['f5']))]).toEqual(['f5'])
  })

  it('when the disk cannot be read, no file is let go on a guess', async () => {
    const { ws, gone, a } = await shared()
    ws.persist!.store.fileIdsIn = async () => {
      throw new Error('disco')
    }
    vi.spyOn(console, 'error').mockImplementation(() => {})
    await ws.load(a)
    await ws.deleteForever(a)
    expect(gone).toEqual([])
  })
})

describe('opening a database late', () => {
  it('a database that finishes opening after another one took over is closed, not mixed in', async () => {
    const first = await NotesStore.open(name)
    const ws = sampleWorkspace()
    ws.goLocal()
    await ws.attach(first)
    ws.newPage('local')
    await ws.detach()

    const other = `${name}-conta`
    const seeded = sampleWorkspace()
    seeded.goAccount()
    await seeded.attach(await NotesStore.open(other))
    seeded.newPage('da conta')
    await seeded.detach()

    let release!: () => void
    const slow = ws.open(async () => {
      await new Promise<void>((r) => (release = r))
      return NotesStore.open(name)
    })
    ws.goAccount()
    await ws.open(() => NotesStore.open(other))
    opened.push(ws)
    release()
    await slow
    expect(ws.pages.map((p) => p.title)).toEqual(['da conta'])
    expect(ws.loading).toBe(false)
    ws.newPage('nova')
    await ws.persist!.flush()
    const db = await openDB(other)
    expect((await db.getAll('pages')).map((p) => p.title).sort()).toEqual(['da conta', 'nova'])
    db.close()
  })

  it('a database that cannot be opened stops the loading and says why to the caller', async () => {
    const ws = sampleWorkspace()
    ws.goLocal()
    await expect(ws.open(async () => Promise.reject(new Error('bloqueado')))).rejects.toThrow('bloqueado')
    expect(ws.loading).toBe(false)
  })
})

describe('importing a file', () => {
  it('keeps the whole text as the body, saved like any page', async () => {
    const ws = await start()
    const page = ws.importPage('Receita', [para('a', 'misture tudo'), para('b', 'asse por 40 min')])
    expect(page.excerpt).toBe('misture tudo')
    expect(page.blocks).toBe(2)
    const again = await restart(ws)
    const id = again.pages[0].id
    await again.load(id)
    expect(again.page(id)!.content!.map((b) => (b as { text: string }).text)).toEqual(['misture tudo', 'asse por 40 min'])
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

describe('one database per account', () => {
  it('names it after the account and refuses an id that does not look like one', () => {
    expect(cloudDbName('11111111-AAAA-bbbb-cccc-222222222222')).toBe('pindrel-cloud-11111111-aaaa-bbbb-cccc-222222222222')
    for (const bad of ['', 'x', '../../etc', 'a b c d e f g h', 'id;drop', '1111111-'.repeat(20)]) expect(() => cloudDbName(bad)).toThrow()
  })

  it('two accounts keep separate notes, and the local ones are a third place', async () => {
    const a = '11111111-1111-1111-1111-111111111111'
    const b = '22222222-2222-2222-2222-222222222222'
    const open = async (store: Promise<NotesStore>) => {
      const ws = sampleWorkspace()
      ws.goAccount()
      await ws.attach(await store)
      opened.push(ws)
      return ws
    }
    const wa = await open(NotesStore.openAccount(a))
    wa.newPage('da Ana')
    await wa.detach()
    const wb = await open(NotesStore.openAccount(b))
    expect(wb.pages).toHaveLength(0)
    wb.newPage('da Bia')
    await wb.detach()
    const again = await open(NotesStore.openAccount(a))
    expect(again.pages.map((p) => p.title)).toEqual(['da Ana'])
  })

  it('goAccount starts empty but keeps the shared list; close drops every note from memory', async () => {
    const ws = sampleWorkspace()
    expect(ws.pages.length).toBeGreaterThan(0)
    ws.view = 'shared'
    ws.goAccount()
    expect(ws.pages).toHaveLength(0)
    expect(ws.local).toBe(false)
    expect(ws.view).toBe('shared')
    ws.goLocal()
    expect(ws.local).toBe(true)
    expect(ws.view).toBe('all')

    ws.goAccount()
    await ws.attach(await NotesStore.openAccount('44444444-4444-4444-4444-444444444444'))
    opened.push(ws)
    ws.newPage('secreta')
    await ws.close()
    expect(ws.pages).toHaveLength(0)
    expect(ws.persist).toBeNull()
    // and what was waiting to be saved still reached the disk
    const back = sampleWorkspace()
    back.goAccount()
    await back.attach(await NotesStore.openAccount('44444444-4444-4444-4444-444444444444'))
    opened.push(back)
    expect(back.pages.map((p) => p.title)).toEqual(['secreta'])
  })
})
