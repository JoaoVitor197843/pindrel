import { fireEvent, render, screen } from '@testing-library/svelte'
import { tick } from 'svelte'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { resetNearView } from '../editor/nearView'
import { Workspace } from '../../stores/workspace.svelte'
import { seedLoad, signInFromAddress } from '../../loadtest'
import { session } from '../../stores/files.svelte'
import Dashboard from '../../../routes/Dashboard.svelte'
import Editor from '../../../routes/Editor.svelte'
import { forgetHeights } from './Lazy.svelte'
import { viewport } from '../../../test/setup'

type Entries = { target: Element; isIntersecting: boolean }[]
let report: (entries: Entries) => void
const watched = new Set<Element>()

beforeEach(() => {
  watched.clear()
  forgetHeights()
  ;(globalThis as Record<string, unknown>).IntersectionObserver = class {
    constructor(cb: (e: Entries) => void) {
      report = cb
    }
    observe(el: Element) {
      watched.add(el)
    }
    unobserve(el: Element) {
      watched.delete(el)
    }
    disconnect() {}
  }
  resetNearView()
  viewport.set(1400)
})
afterEach(() => {
  delete (globalThis as Record<string, unknown>).IntersectionObserver
  resetNearView()
})

const lazies = () => [...document.querySelectorAll<HTMLElement>('[data-lazy]')]
const drawn = () => lazies().filter((l) => l.dataset.lazy === 'drawn')
const show = (els: Element[], isIntersecting: boolean) => report(els.map((target) => ({ target, isIntersecting })))

describe('seedLoad com todos os tipos de bloco (só para medir memória)', () => {
  it('?kinds=mixed enche a página com um de cada tipo, todos válidos e sem repetir identidade', () => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('blocks=400&kinds=mixed'))
    const content = ws.page('p0')!.content!
    const types = new Set(content.map((b) => b.type))
    for (const t of ['heading', 'bullet', 'numbered', 'callout', 'toc', 'bookmark', 'pagelink', 'video', 'audio', 'pdf', 'quote', 'toggle', 'paragraph', 'file', 'image']) expect(types.has(t as never), t).toBe(true)
    expect(new Set(content.map((b) => b.id)).size).toBe(content.length)
    // the page links point at pages that exist
    for (const b of content) if (b.type === 'pagelink') expect(ws.page(b.pageId)).toBeTruthy()
    for (const b of content) if (b.type === 'heading') expect([1, 2, 3]).toContain(b.level ?? 2)
  })
})

describe('seedLoad (só para medir memória)', () => {
  it('cria as páginas e os blocos pedidos, sem chaves repetidas', () => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('pages=300&blocks=50'))
    expect(ws.pages.length).toBe(300)
    expect(new Set(ws.pages.map((p) => p.id)).size).toBe(300)
    expect(ws.pages.every((p) => new Set(p.tags).size === p.tags.length)).toBe(true)
    expect(ws.page('p0')!.content!.length).toBe(7 + 50)
  })

  it('pedidos absurdos ou inválidos são ignorados', () => {
    const ws = new Workspace()
    const before = ws.pages.length
    seedLoad(ws, new URLSearchParams('pages=abc&blocks=-5'))
    seedLoad(ws, new URLSearchParams('pages=1.5&blocks=2.5'))
    expect(ws.pages.length).toBe(before)
    expect(ws.page('p0')!.content?.length ?? 7).toBe(7)
  })
})

describe('dashboard: só os cards perto da tela são desenhados', () => {
  it('com 1000 páginas só os primeiros são desenhados de início, o resto são caixas vazias', () => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('pages=1000'))
    render(Dashboard, { ws })
    expect(screen.queryAllByTestId('page-card').length).toBeLessThan(60)
    expect(lazies().length).toBe(ws.visible.length)
    expect(ws.visible.length).toBeGreaterThan(900)
    expect(lazies().filter((l) => l.dataset.lazy === 'empty').length).toBeGreaterThan(900)
  })

  it('o card chega perto da tela e é desenhado; se afasta e volta a ser uma caixa com a mesma altura', async () => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('pages=200'))
    render(Dashboard, { ws })
    const empty = lazies().find((l) => l.dataset.lazy === 'empty')!
    expect(empty.style.minHeight).toBe('200px')
    show([empty], true)
    await tick()
    expect(empty.dataset.lazy).toBe('drawn')
    expect(empty.querySelector('[data-testid="page-card"]')).toBeTruthy()
    empty.getBoundingClientRect = () => ({ height: 237, top: 0, bottom: 237, left: 0, right: 0, width: 0, x: 0, y: 0, toJSON() {} }) as DOMRect
    show([empty], false)
    await tick()
    expect(empty.dataset.lazy).toBe('empty')
    expect(empty.style.minHeight).toBe('237px')
    expect(empty.querySelector('[data-testid="page-card"]')).toBeNull()
    expect(empty.getAttribute('aria-hidden')).toBe('true')
  })

  it('a lista continua certa: contagem por grupo, busca e troca de lista para grade', async () => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('pages=300'))
    render(Dashboard, { ws })
    expect(lazies().length).toBe(ws.visible.length)
    ws.query = 'Migração'
    await tick()
    expect(screen.getAllByTestId('page-card').length).toBe(1)
    ws.query = ''
    ws.layout = 'list'
    await tick()
    expect(lazies().find((l) => l.dataset.lazy === 'empty')!.style.minHeight).toBe('64px')
  })

  it('sem IntersectionObserver todos os cards são desenhados, como antes', () => {
    delete (globalThis as Record<string, unknown>).IntersectionObserver
    resetNearView()
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('pages=80'))
    render(Dashboard, { ws })
    expect(screen.getAllByTestId('page-card').length).toBe(ws.visible.length)
    expect(lazies().every((l) => l.dataset.lazy === 'drawn')).toBe(true)
  })

  it('sair da tela solta os observadores', () => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('pages=100'))
    const { unmount } = render(Dashboard, { ws })
    expect(watched.size).toBeGreaterThan(90)
    unmount()
    expect(watched.size).toBe(0)
  })
})

describe('editor: só os blocos perto da tela são desenhados', () => {
  const open = (blocks = 400) => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams(`blocks=${blocks}`))
    return { ws, ...render(Editor, { ws, id: 'p0', onback: () => {} }) }
  }
  const rows = () => [...document.querySelectorAll<HTMLElement>('[data-block-id]')]

  it('os primeiros blocos vêm desenhados e os distantes são caixas com data-block-id', () => {
    open()
    expect(rows().length).toBe(7 + 400)
    expect(lazies().filter((l) => l.dataset.lazy === 'empty').length).toBeGreaterThan(300)
    const far = lazies().find((l) => l.dataset.lazy === 'empty')!
    expect(far.getAttribute('data-block-id')).toMatch(/^g\d+$/)
    expect(far.style.minHeight).toMatch(/^\d+px$/)
    expect(far.querySelector('textarea')).toBeNull()
  })

  it('o bloco distante desenha ao chegar perto, e não repete a animação ao voltar', async () => {
    open()
    const far = lazies().find((l) => l.dataset.lazy === 'empty')!
    show([far], true)
    await tick()
    const row = far.querySelector('[data-block-id]')!
    expect(row.className).toContain('animate-rise')
    show([far], false)
    await tick()
    show([far], true)
    await tick()
    expect(far.querySelector('[data-block-id]')!.className).not.toContain('animate-rise')
  })

  it('o sumário leva a um bloco distante e ajusta o pouso quando ele é desenhado', async () => {
    const ws = new Workspace()
    seedLoad(ws, new URLSearchParams('blocks=300'))
    ws.contentOf('p0')
    ws.page('p0')!.content!.splice(250, 0, { id: 'alvo', type: 'heading', text: 'Seção lá longe' })
    const scrolls: string[] = []
    Element.prototype.scrollIntoView = function (this: Element) {
      scrolls.push(this.getAttribute('data-lazy') ?? 'x')
    }
    render(Editor, { ws, id: 'p0', onback: () => {} })
    await fireEvent.click(screen.getByRole('button', { name: 'Seção lá longe' }))
    expect(scrolls[0]).toBe('empty')
    await new Promise((r) => setTimeout(r, 200))
    expect(scrolls.length).toBe(2)
  })

  it('as 3000 linhas não viram 3000 campos de texto nem 3000 componentes desenhados', () => {
    open(3000)
    expect(document.querySelectorAll('textarea').length).toBeLessThan(80)
    expect(drawn().length).toBeLessThan(40)
  })
})

describe('signInFromAddress (só para testar arquivos contra um servidor de verdade)', () => {
  it('aceita um token com a forma de um JWT e ignora o resto', () => {
    session.token = null
    signInFromAddress(new URLSearchParams('token=abc.def.ghi'))
    expect(session.token).toBe('abc.def.ghi')
    session.token = null
    for (const bad of ['token=', 'token=sem pontos', 'token=a.b', 'token=a.b.c.d', 'token=<script>.x.y', 'outro=a.b.c']) {
      signInFromAddress(new URLSearchParams(bad))
      expect(session.token, bad).toBeNull()
    }
  })
})

