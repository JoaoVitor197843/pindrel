import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { instances, type RichInstance } from '../lib/components/editor/rich/engine'
import { resetNearView } from '../lib/components/editor/nearView'
import { toast } from '../lib/stores/toast.svelte'
import { Workspace } from '../lib/stores/workspace.svelte'
import { viewport } from '../test/setup'
import Editor from './Editor.svelte'

beforeEach(() => {
  viewport.set(1400)
  toast.message = ''
  ws = new Workspace()
})
afterEach(() => {
  cleanup()
  resetNearView()
})

let ws: Workspace
const open = () => render(Editor, { ws, id: 'p0', onback: vi.fn() })
const para = () => screen.getByRole('textbox', { name: 'Parágrafo' })
const block = (n = 1) => ws.page('p0')!.content![n] as { text: string }

/** Focuses the first paragraph and waits for the engine to take its place. */
async function edit(label = 'Parágrafo') {
  const view = screen.getByRole('textbox', { name: label })
  view.focus()
  await waitFor(() => expect(document.querySelector('[data-rich]')).not.toBeNull())
  const host = document.querySelector<HTMLElement>('[data-rich]')!
  await waitFor(() => expect(instances.get(host)).toBeTruthy())
  return { host, inst: instances.get(host) as RichInstance, dom: host.querySelector<HTMLElement>('[contenteditable]')! }
}

describe('Editor com texto rico (TipTap) — só o bloco em foco é um editor', () => {

  it('em repouso nenhum bloco tem campo nem editor: são só texto', () => {
    open()
    expect(document.querySelectorAll('textarea[data-fmt]').length).toBe(0)
    expect(document.querySelectorAll('[data-rich]').length).toBe(0)
    expect(para().tagName).toBe('DIV')
  })

  it('ao focar, o editor ocupa o lugar do texto, com o mesmo conteúdo e nome acessível', async () => {
    open()
    const before = para().textContent
    const { dom } = await edit()
    expect(dom.getAttribute('contenteditable')).toBe('true')
    expect(dom.getAttribute('role')).toBe('textbox')
    expect(dom.getAttribute('aria-label')).toBe('Parágrafo')
    expect(dom.textContent).toBe(before)
    expect(document.querySelectorAll('[data-rich]').length).toBe(1)
  })

  it('ao sair, volta a ser só texto, já formatado', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(2, 12)
    inst.toggle('bold')
    expect(block().text).toContain('**fechamento**')
    await fireEvent.blur(dom)
    await waitFor(() => expect(document.querySelectorAll('[data-rich]').length).toBe(0))
    expect(para().querySelector('strong')!.textContent).toBe('fechamento')
  })

  it('fechar os símbolos formata na hora e o texto seguinte sai sem formato', async () => {
    open()
    const { inst } = await edit()
    const end = inst.runs().reduce((n, r) => n + r.text.length, 0)
    inst.replace(end, end, [{ text: ' **forte**', marks: {} }])
    expect(block().text.endsWith(' **forte**')).toBe(true)
    expect(inst.runs().at(-1)).toEqual({ text: 'forte', marks: { bold: true } })
    expect(inst.runs().map((r) => r.text).join('')).not.toContain('*')
    // the next letters are plain
    const now = inst.runs().reduce((n, r) => n + r.text.length, 0)
    inst.replace(now, now, [{ text: ' fim', marks: {} }])
    expect(inst.runs().at(-1)).toEqual({ text: ' fim', marks: {} })
  })

  it('cada símbolo vira sua marca: itálico *x*, sublinhado __x__, riscado ~~x~~, código `x`', async () => {
    open()
    const { inst } = await edit()
    const add = (s: string) => {
      const n = inst.runs().reduce((a, r) => a + r.text.length, 0)
      inst.replace(n, n, [{ text: s, marks: {} }])
    }
    add(' *i*')
    add(' __u__')
    add(' ~~s~~')
    add(' `c`')
    const marks = inst.runs().filter((r) => Object.keys(r.marks).length).map((r) => Object.keys(r.marks)[0])
    expect(marks).toEqual(['italic', 'underline', 'strike', 'code'])
    expect(block().text.endsWith(' *i* __u__ ~~s~~ `c`')).toBe(true)
  })

  it('Ctrl+B, Ctrl+I, Ctrl+U e Ctrl+Shift+S alternam as marcas na seleção', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(2, 12)
    await fireEvent.keyDown(dom, { key: 'b', ctrlKey: true })
    await fireEvent.keyDown(dom, { key: 'i', ctrlKey: true })
    await fireEvent.keyDown(dom, { key: 'u', ctrlKey: true })
    await fireEvent.keyDown(dom, { key: 's', ctrlKey: true, shiftKey: true })
    expect(Object.keys(inst.runs().find((r) => r.text === 'fechamento')!.marks).sort()).toEqual(['bold', 'italic', 'strike', 'underline'])
    await fireEvent.keyDown(dom, { key: 'b', ctrlKey: true })
    expect(inst.runs().find((r) => r.text === 'fechamento')!.marks.bold).toBeUndefined()
  })

  it('link na seleção entra como [texto](endereço) e sai com null', async () => {
    open()
    const { inst } = await edit()
    inst.setSelection(2, 12)
    inst.setLink('https://exemplo.com')
    expect(block().text).toContain('[fechamento](https://exemplo.com)')
    inst.setLink(null)
    expect(block().text).not.toContain('](')
  })

  it('Enter parte o bloco no cursor e leva o cursor ao novo bloco; marcas partidas fecham dos dois lados', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(0, inst.runs().reduce((a, r) => a + r.text.length, 0))
    inst.toggle('bold')
    inst.setSelection(10, 10)
    const count = ws.page('p0')!.content!.length
    await fireEvent.keyDown(dom, { key: 'Enter' })
    const content = ws.page('p0')!.content!
    expect(content.length).toBe(count + 1)
    const [head, tail] = [content[1], content[2]] as { text: string }[]
    expect(head.text.startsWith('**') && head.text.endsWith('**')).toBe(true)
    expect(tail.text.startsWith('**') && tail.text.endsWith('**')).toBe(true)
    await waitFor(() => expect(document.querySelector('[data-rich]')).not.toBeNull())
  })

  it('Shift+Enter põe uma quebra de linha no mesmo bloco', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(3, 3)
    const count = ws.page('p0')!.content!.length
    await fireEvent.keyDown(dom, { key: 'Enter', shiftKey: true })
    expect(ws.page('p0')!.content!.length).toBe(count)
    expect(block().text.slice(3, 4)).toBe('\n')
  })

  it('"/" num parágrafo vazio abre o menu de inserir, e Backspace num vazio apaga o bloco', async () => {
    open()
    const { inst } = await edit()
    const n = inst.runs().reduce((a, r) => a + r.text.length, 0)
    inst.replace(0, n, [{ text: '/', marks: {} }])
    await waitFor(() => expect(screen.getByRole('menu', { name: /Inserir/i })).toBeTruthy())
    expect(block().text).toBe('')
  })

  it('Backspace num bloco vazio remove o bloco', async () => {
    open()
    const { inst, dom } = await edit()
    const n = inst.runs().reduce((a, r) => a + r.text.length, 0)
    inst.replace(0, n, [])
    const count = ws.page('p0')!.content!.length
    await fireEvent.keyDown(dom, { key: 'Backspace' })
    expect(ws.page('p0')!.content!.length).toBe(count - 1)
  })

  it('a barra de formatação aparece com texto selecionado e aplica no motor', async () => {
    open()
    const { inst } = await edit()
    inst.setSelection(2, 12)
    document.dispatchEvent(new Event('selectionchange'))
    const bar = await screen.findByRole('toolbar', { name: 'Formatar texto' })
    await fireEvent.click(bar.querySelector('[aria-label="Riscado"]')!)
    expect(block().text).toContain('~~fechamento~~')
  })

  it('bloco seguro continua sendo campo comum, sem motor', () => {
    ws.unlockVault('1234')
    open()
    expect(document.querySelectorAll('[data-rich]').length).toBe(0)
  })

  it('texto estranho e enorme não trava nem perde letras', async () => {
    open()
    const { inst } = await edit()
    const odd = '*'.repeat(500) + ' ~~ __ ` [ ]( ' + 'a'.repeat(3000) + '\n\n' + '<b>&amp;</b>'
    inst.replace(0, inst.runs().reduce((a, r) => a + r.text.length, 0), [{ text: odd, marks: {} }])
    expect(inst.runs().map((r) => r.text).join('')).toContain('<b>&amp;</b>')
    expect(block().text).toContain('<b>&amp;</b>')
  })

  it('o link pode ser digitado: o campo do endereço tira o foco do texto e o bloco continua aberto', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(2, 12)
    document.dispatchEvent(new Event('selectionchange'))
    const bar = await screen.findByRole('toolbar', { name: 'Formatar texto' })
    await fireEvent.click(bar.querySelector('[aria-label="Link"]')!)
    const input = (await screen.findByLabelText('Endereço do link')) as HTMLInputElement
    // the address field took the focus: the text loses it, without any element of the bar to receive it in some browsers
    await fireEvent.blur(dom, { relatedTarget: null })
    document.dispatchEvent(new Event('selectionchange'))
    expect(document.querySelector('[data-rich]')).not.toBeNull()
    expect(screen.getByRole('toolbar', { name: 'Formatar texto' })).toBeTruthy()
    await fireEvent.input(input, { target: { value: 'exemplo.com' } })
    await fireEvent.submit(input.closest('form')!)
    expect(block().text).toContain('[fechamento](https://exemplo.com)')
    expect(screen.queryByLabelText('Endereço do link')).toBeNull()
    expect(inst.selection()).toEqual({ from: 2, to: 12 })
  })

  it('cancelar o link devolve a seleção ao texto e libera o bloco para fechar de novo', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(2, 12)
    document.dispatchEvent(new Event('selectionchange'))
    const bar = await screen.findByRole('toolbar', { name: 'Formatar texto' })
    await fireEvent.click(bar.querySelector('[aria-label="Link"]')!)
    await screen.findByLabelText('Endereço do link')
    await fireEvent.click(screen.getByRole('button', { name: 'Cancelar link' }))
    expect(inst.selection()).toEqual({ from: 2, to: 12 })
    expect(block().text).not.toContain('](')
    await fireEvent.blur(dom, { relatedTarget: null })
    await waitFor(() => expect(document.querySelectorAll('[data-rich]').length).toBe(0))
  })

  it('endereço inválido avisa e mantém o campo aberto', async () => {
    open()
    const { inst } = await edit()
    inst.setSelection(2, 12)
    document.dispatchEvent(new Event('selectionchange'))
    const bar = await screen.findByRole('toolbar', { name: 'Formatar texto' })
    await fireEvent.click(bar.querySelector('[aria-label="Link"]')!)
    const input = (await screen.findByLabelText('Endereço do link')) as HTMLInputElement
    await fireEvent.input(input, { target: { value: 'javascript:alert(1)' } })
    await fireEvent.submit(input.closest('form')!)
    expect(toast.message).toMatch(/Endereço inválido/)
    expect(screen.getByLabelText('Endereço do link')).toBeTruthy()
    expect(block().text).not.toContain('javascript')
  })

  it('todas as marcas na seleção inteira saem como símbolos e voltam como marcas, sem acumular asteriscos', async () => {
    open()
    const { inst, dom } = await edit()
    const len = inst.runs().reduce((a, r) => a + r.text.length, 0)
    inst.replace(0, len, [{ text: 'hello', marks: {} }])
    inst.setSelection(0, 5)
    for (const m of ['bold', 'underline', 'strike', 'italic'] as const) inst.toggle(m)
    expect(block().text).toBe('**__~~*hello*~~__**')
    await fireEvent.blur(dom)
    await waitFor(() => expect(document.querySelectorAll('[data-rich]').length).toBe(0))
    const view = para()
    expect(view.textContent).toBe('hello')
    expect(view.querySelector('strong u s em')!.textContent).toBe('hello')
    // editing again shows the marks, and bold on and off does not pile up symbols
    const again = await edit()
    expect(again.inst.runs()).toEqual([{ text: 'hello', marks: { bold: true, underline: true, strike: true, italic: true } }])
    again.inst.setSelection(0, 5)
    again.inst.toggle('bold')
    expect(block().text).toBe('__~~*hello*~~__')
    again.inst.toggle('bold')
    expect(block().text).toBe('**__~~*hello*~~__**')
  })

  it('hello** e depois ** no começo: vira negrito (os símbolos do começo e do fim sobem juntos)', async () => {
    open()
    const { inst } = await edit()
    const len = inst.runs().reduce((a, r) => a + r.text.length, 0)
    inst.replace(0, len, [{ text: 'hello**', marks: {} }])
    expect(block().text).toBe('hello**')
    inst.replace(0, 0, [{ text: '**', marks: {} }])
    expect(inst.runs()).toEqual([{ text: 'hello', marks: { bold: true } }])
    expect(block().text).toBe('**hello**')
  })

  it('o sublinhado fora da edição não usa a cor de destaque', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(2, 12)
    inst.toggle('underline')
    await fireEvent.blur(dom)
    await waitFor(() => expect(document.querySelectorAll('[data-rich]').length).toBe(0))
    expect(para().className).not.toContain('decoration-accent')
  })

  it('na tela de toque a barra fica embaixo, longe do menu de copiar e colar do sistema', async () => {
    const real = window.matchMedia
    window.matchMedia = ((q: string) => ({ ...real(q), matches: q.includes('pointer: coarse') ? true : real(q).matches })) as typeof window.matchMedia
    try {
      open()
      const { inst } = await edit()
      inst.setSelection(2, 12)
      document.dispatchEvent(new Event('selectionchange'))
      const bar = (await screen.findByRole('toolbar', { name: 'Formatar texto' })) as HTMLElement
      expect(bar.style.left).toBe('8px')
      expect(bar.style.right).toBe('8px')
      expect(parseInt(bar.style.top)).toBe(window.innerHeight - 56)
    } finally {
      window.matchMedia = real
    }
  })

  it('marca-texto: Ctrl+Shift+H e pelo símbolo ==, e volta a ser texto com o símbolo', async () => {
    open()
    const { inst, dom } = await edit()
    inst.setSelection(2, 12)
    await fireEvent.keyDown(dom, { key: 'H', ctrlKey: true, shiftKey: true })
    expect(block().text).toContain('==fechamento==')
    const end = inst.runs().reduce((a, r) => a + r.text.length, 0)
    inst.replace(end, end, [{ text: ' ==fim==', marks: {} }])
    expect(inst.runs().at(-1)).toEqual({ text: 'fim', marks: { highlight: true } })
    await fireEvent.blur(dom)
    await waitFor(() => expect(document.querySelectorAll('[data-rich]').length).toBe(0))
    expect(para().querySelectorAll('mark').length).toBe(2)
  })

  it('o limite de caracteres vale dentro do motor', async () => {
    open()
    const { inst } = await edit()
    const end = inst.runs().reduce((a, r) => a + r.text.length, 0)
    inst.replace(end, end, [{ text: 'x'.repeat(30000), marks: {} }])
    await waitFor(() => expect(inst.runs().reduce((a, r) => a + r.text.length, 0)).toBeLessThanOrEqual(20000))
    expect(block().text.length).toBeLessThanOrEqual(20000)
  })

  it('colar várias linhas vira um só bloco com quebras, e colar um endereço sobre palavras faz o link', async () => {
    open()
    const { inst, dom } = await edit()
    const paste = (types: Record<string, string>) => {
      const e = new Event('paste', { bubbles: true, cancelable: true }) as Event & { clipboardData: unknown }
      e.clipboardData = { getData: (t: string) => types[t] ?? '', types: Object.keys(types), files: [], items: [] }
      dom.dispatchEvent(e)
    }
    inst.setSelection(2, 12)
    paste({ 'text/plain': 'https://exemplo.com' })
    await waitFor(() => expect(block().text).toContain('[fechamento](https://exemplo.com)'))
    const count = ws.page('p0')!.content!.length
    inst.replace(0, inst.runs().reduce((a, r) => a + r.text.length, 0), [])
    inst.setSelection(0, 0)
    paste({ 'text/plain': 'linha um\nlinha dois', 'text/html': '<p>linha um</p><p>linha dois</p>' })
    await waitFor(() => expect(block().text).toBe('linha um\nlinha dois'))
    expect(ws.page('p0')!.content!.length).toBe(count)
  })

  it('bloco vazio mostra a dica, desenhada pelo próprio editor', async () => {
    open()
    const view = screen.getByRole('textbox', { name: 'Título de seção' })
    view.focus()
    await waitFor(() => expect(document.querySelector('[data-rich]')).not.toBeNull())
    const host = document.querySelector<HTMLElement>('[data-rich]')!
    await waitFor(() => expect(instances.get(host)).toBeTruthy())
    const inst = instances.get(host)!
    inst.replace(0, inst.runs().reduce((a, r) => a + r.text.length, 0), [])
    await waitFor(() => {
      expect(host.querySelector('p.is-empty')?.getAttribute('data-placeholder')).toBe('Título')
    })
    expect(inst.nativePlaceholder).toBe(true)
  })

  it('o bloco que está sendo editado não é tirado da tela quando sai da zona de desenho', async () => {
    let observer = null as ((e: Partial<IntersectionObserverEntry>[]) => void) | null
    ;(globalThis as { IntersectionObserver?: unknown }).IntersectionObserver = class {
      constructor(cb: (e: Partial<IntersectionObserverEntry>[]) => void) {
        observer = cb
      }
      observe() {}
      unobserve() {}
      disconnect() {}
    }
    resetNearView()
    open()
    // everything near, then a notice that the first block is far: it has the focus and stays
    const { dom } = await edit()
    dom.focus()
    ;(observer as ((e: unknown[]) => void) | null)?.([...document.querySelectorAll('[data-lazy]')].map((target) => ({ target, isIntersecting: false })))
    await new Promise((r) => setTimeout(r, 30))
    expect(document.querySelector('[data-rich]')).not.toBeNull()
  })
})
