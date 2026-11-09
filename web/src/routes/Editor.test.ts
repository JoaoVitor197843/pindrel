import axe from 'axe-core'
import { sampleWorkspace } from '../lib/sample'
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { tick } from 'svelte'
import { resetNearView } from '../lib/components/editor/nearView'
import { instances, type RichInstance } from '../lib/components/editor/rich/engine'
import type { Block } from '../lib/stores/blocks'
import { FakeFiles, patterned } from '../test/fakeFiles'
import { session } from '../lib/stores/files.svelte'
import { prefs } from '../lib/stores/prefs.svelte'
import { toast } from '../lib/stores/toast.svelte'
import { Workspace } from '../lib/stores/workspace.svelte'
import { viewport } from '../test/setup'
import { stubLocalStorage } from '../test/storage'
import Editor from './Editor.svelte'

let ws: Workspace
const click = (el: HTMLElement) => fireEvent.click(el)
const type = (el: HTMLElement, value: string) => fireEvent.input(el, { target: { value } })
const keys = (el: Element | Window, key: string, init: KeyboardEventInit = {}) => fireEvent.keyDown(el, { key, ...init })
const blockEls = () => [...document.querySelectorAll<HTMLElement>('[data-block-id]')]
const kindsOf = () => blockEls().map((b) => b.getAttribute('aria-label')!.replace(/ \d+ de \d+$/, ''))
const open = (id = 'p0', onback = vi.fn()) => render(Editor, { ws, id, onback })
const menuItem = (name: string) => screen.getByRole('menuitem', { name })
const caret = (el: HTMLTextAreaElement | HTMLInputElement, at: number, to = at) => el.setSelectionRange(at, to)

/** A text block is drawn text until it is focused; this focuses it and gives the rich-text editor that takes its place. */
async function rich(label = 'Parágrafo') {
  ;(document.activeElement as HTMLElement | null)?.blur?.()
  screen.getByRole('textbox', { name: label }).focus()
  await waitFor(() => expect(document.querySelector(`[data-rich] [aria-label="${label}"]`)).not.toBeNull())
  return current(label)
}
/** The editor that is open now (the one of the block with this label). */
function current(label = 'Parágrafo') {
  const dom = document.querySelector<HTMLElement>(`[data-rich] [aria-label="${label}"]`)!
  const host = dom.closest<HTMLElement>('[data-rich]')!
  return { inst: instances.get(host) as RichInstance, dom, host }
}
const plain = (inst: RichInstance) => inst.runs().map((r) => r.text).join('')
/** Types a whole text in place of what the block had, through the editor itself. */
async function put(inst: RichInstance, text: string) {
  inst.replace(0, plain(inst).length, text ? [{ text, marks: {} }] : [])
  await tick()
}
const drawn = (label = 'Parágrafo') => screen.getByRole('textbox', { name: label })
const noEditor = () => expect(document.querySelector('[data-rich]')).toBeNull()

async function violations(): Promise<string[]> {
  const result = await axe.run(document.body, { rules: { 'color-contrast': { enabled: false }, region: { enabled: false } } })
  return result.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.html.slice(0, 90)).join(' | ')}`)
}

beforeEach(() => {
  ws = sampleWorkspace()
  toast.message = ''
  viewport.set(1400)
})
afterEach(() => vi.useRealTimers())

describe('Editor — a página do design', () => {
  it('mostra título, metadados, tags e todos os blocos na ordem', () => {
    open()
    expect((screen.getByLabelText('Título da página') as HTMLTextAreaElement).value).toBe('Rotina de encerramento do trimestre')
    const meta = screen.getByTestId('meta').textContent!
    expect(meta).toMatch(/Criada\s*\d{2} \w{3} \d{4}/)
    expect(meta).toMatch(/Editada\s*há/)
    expect(meta).toContain('7 blocos')
    expect(meta).toContain('2 de 4 feitas')
    const tags = within(screen.getByRole('group', { name: 'Tags da página' }))
    expect(tags.getByText(/#operações/)).toBeTruthy()
    expect(tags.getByText(/#trimestral/)).toBeTruthy()
    expect(kindsOf()).toEqual(['Título de seção', 'Parágrafo', 'Checklist', 'Bloco de código', 'Spoiler', 'Bloco seguro', 'Tabela'])
    expect(screen.getByRole('status', { name: '' }).textContent).toContain('salvo automaticamente')
  })

  it('o spoiler e o bloco seguro não põem o texto escondido na página', () => {
    open()
    expect(document.body.textContent).not.toContain('corte de 12%')
    expect(document.body.textContent).not.toContain('PNDR-4471')
    expect(document.body.textContent).not.toContain('Plany')
  })

  it('"Dashboard" chama o callback de voltar', async () => {
    const onback = vi.fn()
    open('p0', onback)
    await click(screen.getByRole('button', { name: /Dashboard/ }))
    expect(onback).toHaveBeenCalledOnce()
  })

  it('página que não existe oferece voltar', async () => {
    const onback = vi.fn()
    open('nao-existe', onback)
    expect(screen.getByRole('heading', { name: 'Página não encontrada' })).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Voltar ao dashboard' }))
    expect(onback).toHaveBeenCalled()
  })

  it('uma página antiga abre com o resumo como parágrafo', () => {
    open('p5')
    expect(drawn().textContent).toContain('Levain')
  })
})

describe('Editor — título, texto e salvamento', () => {
  it('editar o título muda a página e o cartão; Enter vai para o primeiro bloco sem criar linha', async () => {
    open()
    const title = screen.getByLabelText('Título da página') as HTMLTextAreaElement
    await type(title, 'Novo nome')
    expect(ws.page('p0')!.title).toBe('Novo nome')
    await keys(title, 'Enter')
    expect(document.activeElement).toBe(screen.getByLabelText('Título de seção'))
    expect(title.value).toBe('Novo nome')
  })

  it('o indicador mostra "salvando…" e depois "salvo automaticamente"', async () => {
    open()
    const { inst } = await rich()
    vi.useFakeTimers()
    await put(inst, 'mudou')
    expect(screen.getByRole('status', { name: '' }).textContent).toContain('salvando…')
    await vi.advanceTimersByTimeAsync(700)
    expect(screen.getByRole('status', { name: '' }).textContent).toContain('salvo automaticamente')
  })

  it('editar o primeiro texto atualiza o resumo do cartão no dashboard', async () => {
    open()
    const { inst } = await rich('Título de seção')
    await put(inst, 'Primeira linha nova')
    expect(ws.page('p0')!.excerpt).toBe('Primeira linha nova')
    expect(ws.page('p0')!.blocks).toBe(7)
  })

  it('texto gigante não passa do limite e HTML digitado vira só texto', async () => {
    open()
    const { inst } = await rich()
    await put(inst, 'x'.repeat(50_000))
    expect((ws.page('p0')!.content![1] as { text: string }).text.length).toBeLessThanOrEqual(20_000)
    await put(inst, '<img src=x onerror=alert(1)>')
    expect(document.querySelector('img')).toBeNull()
    expect(plain(inst)).toBe('<img src=x onerror=alert(1)>')
  })

  it('Enter no meio do parágrafo divide em dois e leva o cursor ao novo', async () => {
    open('p5')
    const { inst, dom } = await rich()
    await put(inst, 'abcdef')
    inst.setSelection(2, 2)
    await keys(dom, 'Enter')
    await fireEvent.blur(dom) // the focus moved to the new block, as it does in a browser
    await tick()
    expect(screen.getAllByRole('textbox', { name: 'Parágrafo' }).map((x) => x.textContent)).toEqual(['ab', 'cdef'])
    expect((ws.page('p5')!.content!.map((b) => (b as { text: string }).text))).toEqual(['ab', 'cdef'])
    await waitFor(() => expect(document.querySelectorAll('[data-rich]').length).toBeGreaterThan(0))
  })

  it('Shift+Enter não divide: fica a quebra de linha dentro do bloco', async () => {
    open('p5')
    const { inst, dom } = await rich()
    inst.setSelection(1, 1)
    await keys(dom, 'Enter', { shiftKey: true })
    expect(screen.getAllByRole('textbox', { name: 'Parágrafo' })).toHaveLength(1)
    expect(plain(inst).slice(1, 2)).toBe('\n')
  })

  it('Backspace num parágrafo vazio apaga o bloco e volta o cursor para o anterior', async () => {
    open()
    const { inst, dom } = await rich()
    await put(inst, '')
    await keys(dom, 'Backspace')
    expect(screen.queryByRole('textbox', { name: 'Parágrafo' })).toBeNull()
    expect(kindsOf()).toHaveLength(6)
    await waitFor(() => expect(document.querySelector('[data-rich] [aria-label="Título de seção"]')).not.toBeNull())
  })

  it('Backspace com texto só apaga letras (nunca o bloco)', async () => {
    open()
    await keys(screen.getByLabelText('Parágrafo'), 'Backspace')
    expect(kindsOf()).toHaveLength(7)
  })

  it('apagar o primeiro bloco devolve o cursor ao título', async () => {
    open('p5')
    const { inst, dom } = await rich()
    await put(inst, '')
    await keys(dom, 'Backspace')
    expect(kindsOf()).toEqual([])
    await waitFor(() => expect(document.activeElement).toBe(screen.getByLabelText('Título da página')))
  })
})

describe('Editor — navegação por setas', () => {
  it('seta para baixo no fim do campo vai para o próximo; no meio do texto anda dentro dele', async () => {
    open()
    const title = screen.getByLabelText('Título da página') as HTMLTextAreaElement
    title.focus()
    caret(title, 3)
    expect(await keys(title, 'ArrowDown')).toBe(true) // not cancelled: the caret just moves
    caret(title, title.value.length)
    expect(await keys(title, 'ArrowDown')).toBe(false)
    await waitFor(() => expect(document.querySelector('[data-rich] [aria-label="Título de seção"]')).not.toBeNull())
    expect(current('Título de seção').inst.selection()).toEqual({ from: 0, to: 0 })
  })

  it('seta para cima no começo volta ao campo anterior, com o cursor no fim', async () => {
    open()
    const { inst, dom } = await rich('Título de seção')
    inst.setSelection(0, 0)
    await keys(dom, 'ArrowUp')
    const title = screen.getByLabelText('Título da página') as HTMLTextAreaElement
    expect(document.activeElement).toBe(title)
    expect(title.selectionStart).toBe(title.value.length)
  })

  it('com texto selecionado, ou com Shift/Ctrl, não sai do campo', async () => {
    open()
    const { inst, dom } = await rich()
    inst.setSelection(0, 5)
    expect(await keys(dom, 'ArrowUp')).toBe(true)
    inst.setSelection(0, 0)
    expect(await keys(dom, 'ArrowUp', { shiftKey: true })).toBe(true)
    expect(await keys(dom, 'ArrowUp', { ctrlKey: true })).toBe(true)
    expect(document.querySelector('[data-rich] [aria-label="Parágrafo"]')).not.toBeNull()
  })

  it('o primeiro e o último campo não vão a lugar nenhum', async () => {
    open()
    const title = screen.getByLabelText('Título da página') as HTMLTextAreaElement
    title.focus()
    caret(title, 0)
    expect(await keys(title, 'ArrowUp')).toBe(true)
    const draft = screen.getByLabelText('Nova linha') as HTMLTextAreaElement
    draft.focus()
    expect(await keys(draft, 'ArrowDown')).toBe(true)
  })
})

describe('Editor — inserir blocos', () => {
  it('"+" abre o menu com as opções; escolher cria o bloco logo depois e fecha o menu', async () => {
    open()
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    const menu = within(screen.getByRole('menu', { name: 'Inserir bloco' }))
    expect(menu.getAllByRole('menuitem').map((m) => m.textContent!.trim().replace(/^\S+\s+/, ''))).toEqual(
      expect.arrayContaining(['Texto', 'Título 1', 'Título 2', 'Título 3', 'Lista com marcadores', 'Lista numerada', 'Checklist', 'Código', 'Imagem', 'Vídeo', 'Áudio', 'PDF', 'Tabela', 'Link', 'Link para página', 'Sumário', 'Spoiler', 'Bloco seguro']),
    )
    await click(menu.getByRole('menuitem', { name: /Checklist/ }))
    expect(screen.queryByRole('menu', { name: 'Inserir bloco' })).toBeNull()
    expect(kindsOf().slice(1, 4)).toEqual(['Parágrafo', 'Checklist', 'Checklist'])
    await waitFor(() => expect(document.activeElement).toBe(document.querySelectorAll('[data-block-id]')[2].querySelector('[data-nav]')))
  })

  it('Esc fecha o menu; as setas andam por ele; clicar fora fecha', async () => {
    open()
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    const items = screen.getAllByRole('menuitem')
    await waitFor(() => expect(document.activeElement).toBe(items[0]))
    await keys(items[0], 'ArrowDown')
    expect(document.activeElement).toBe(items[1])
    await keys(items[1], 'ArrowUp')
    await keys(items[0], 'ArrowUp')
    expect(document.activeElement).toBe(items.at(-1))
    await keys(items.at(-1)!, 'Escape')
    expect(screen.queryByRole('menu', { name: 'Inserir bloco' })).toBeNull()
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    await fireEvent.mouseDown(document.body)
    expect(screen.queryByRole('menu', { name: 'Inserir bloco' })).toBeNull()
  })

  it('"/" na linha vazia do fim abre o menu e escolher cria o bloco no fim', async () => {
    open()
    const draft = screen.getByLabelText('Nova linha') as HTMLTextAreaElement
    await type(draft, '/')
    expect(draft.value).toBe('')
    await click(screen.getByRole('menuitem', { name: /^Título 2$/ }))
    expect(kindsOf().at(-1)).toBe('Título de seção')
    expect(kindsOf()).toHaveLength(8)
  })

  it('texto digitado na linha do fim vira um parágrafo e a linha esvazia', async () => {
    open()
    const draft = screen.getByLabelText('Nova linha') as HTMLTextAreaElement
    await type(draft, 'o')
    expect(kindsOf().at(-1)).toBe('Parágrafo')
    expect(draft.value).toBe('')
    expect(screen.getAllByRole('textbox', { name: 'Parágrafo' }).at(-1)!.textContent).toBe('o')
    await keys(draft, 'Enter')
    expect(kindsOf()).toHaveLength(8) // Enter in the empty line adds nothing
  })

  it('"/" num parágrafo vazio abre o menu e o novo bloco o substitui', async () => {
    open('p5')
    const { inst } = await rich()
    await put(inst, '/')
    await click(await screen.findByRole('menuitem', { name: /Código/ }))
    expect(kindsOf()).toEqual(['Bloco de código'])
  })

  it('"/" no meio de um texto é só uma barra', async () => {
    open('p5')
    const { inst } = await rich()
    await put(inst, 'a/b')
    expect(screen.queryByRole('menu')).toBeNull()
    expect(plain(inst)).toBe('a/b')
  })

  it('cada tipo do menu cria o bloco certo', async () => {
    open('p5')
    const cases: [RegExp, string][] = [
      [/Texto/, 'Parágrafo'],
      [/^Título 1$/, 'Título de seção'],
      [/^Título 2$/, 'Título de seção'],
      [/^Título 3$/, 'Título de seção'],
      [/Título 2 com toggle/, 'Título de seção'],
      [/Lista com marcadores/, 'Item de lista'],
      [/Lista numerada/, 'Item numerado'],
      [/^Link$/, 'Link'],
      [/Link para página/, 'Link para página'],
      [/Vídeo/, 'Vídeo'],
      [/Áudio/, 'Áudio'],
      [/PDF/, 'PDF'],
      [/Sumário/, 'Sumário'],
      [/Checklist/, 'Checklist'],
      [/Código/, 'Bloco de código'],
      [/Imagem/, 'Imagem'],
      [/Tabela/, 'Tabela'],
      [/Spoiler/, 'Spoiler'],
      [/Bloco seguro/, 'Bloco seguro'],
    ]
    for (const [name, label] of cases) {
      await type(screen.getByLabelText('Nova linha'), '/')
      await click(screen.getByRole('menuitem', { name }))
      expect(kindsOf().at(-1)).toBe(label)
    }
  })

  it('no limite de blocos avisa em vez de criar', async () => {
    open('p5')
    for (let i = 0; i < 520; i++) {
      const made = ws.contentOf('p5')!
      if (made.length < 500) made.push({ id: `f${i}`, type: 'paragraph', text: '' })
    }
    await type(screen.getByLabelText('Nova linha'), '/')
    await click(screen.getByRole('menuitem', { name: /Texto/ }))
    expect(toast.message).toContain('Limite')
  })
})

describe('Editor — mover e apagar blocos', () => {
  it('o menu do alça sobe, desce e exclui; os extremos ficam desabilitados', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Opções de Título de seção 1' }))
    expect((menuItem('Subir') as HTMLButtonElement).disabled).toBe(true)
    await click(menuItem('Descer'))
    expect(kindsOf().slice(0, 2)).toEqual(['Parágrafo', 'Título de seção'])
    await click(screen.getByRole('button', { name: 'Opções de Título de seção 2' }))
    await click(menuItem('Excluir'))
    expect(kindsOf()).toHaveLength(6)
    expect(screen.queryByLabelText('Título de seção')).toBeNull()
  })

  it('Alt + seta na alça move o bloco pelo teclado', async () => {
    open()
    const handle = screen.getByRole('button', { name: 'Opções de Título de seção 1' })
    await keys(handle, 'ArrowDown', { altKey: true })
    expect(kindsOf().slice(0, 2)).toEqual(['Parágrafo', 'Título de seção'])
    await keys(screen.getByRole('button', { name: 'Opções de Título de seção 2' }), 'ArrowUp', { altKey: true })
    expect(kindsOf()[0]).toBe('Título de seção')
  })

  it('arrastar a alça solta o bloco antes do bloco de destino', async () => {
    open()
    const handle = screen.getByRole('button', { name: 'Opções de Título de seção 1' })
    const target = blockEls()[3]
    const dataTransfer = { effectAllowed: '', setData: vi.fn() }
    await fireEvent.dragStart(handle, { dataTransfer })
    await fireEvent.dragOver(target, { dataTransfer })
    await fireEvent.drop(target, { dataTransfer })
    // dropped before the 4th block (the code): the heading now sits right before it
    expect(kindsOf().slice(0, 4)).toEqual(['Parágrafo', 'Checklist', 'Título de seção', 'Bloco de código'])
  })

  it('soltar sem ter arrastado um bloco não faz nada', async () => {
    open()
    await fireEvent.dragOver(blockEls()[2], {})
    await fireEvent.drop(blockEls()[2], {})
    expect(kindsOf()[0]).toBe('Título de seção')
  })
})

describe('Editor — checklist', () => {
  it('marcar muda o progresso, o risco e o texto de metadados', async () => {
    open()
    const box = screen.getByRole('checkbox', { name: /Rodar o export/ })
    expect(box.getAttribute('aria-checked')).toBe('false')
    await click(box)
    expect(box.getAttribute('aria-checked')).toBe('true')
    expect(screen.getByTestId('meta').textContent).toContain('3 de 4 feitas')
    expect((screen.getByLabelText('Item 3') as HTMLTextAreaElement).className).toContain('line-through')
    await click(box)
    expect(screen.getByTestId('meta').textContent).toContain('2 de 4 feitas')
  })

  it('Enter cria um item novo logo abaixo e foca nele', async () => {
    open()
    await keys(screen.getByLabelText('Item 2'), 'Enter')
    const items = screen.getAllByLabelText(/^Item \d/) as HTMLTextAreaElement[]
    expect(items).toHaveLength(5)
    expect(items[2].value).toBe('')
    await waitFor(() => expect(document.activeElement).toBe(items[2]))
  })

  it('Enter num item vazio encerra a lista: o item some e um parágrafo aparece depois', async () => {
    open()
    await keys(screen.getByLabelText('Item 4'), 'Enter')
    const empty = screen.getByLabelText('Item 5')
    await keys(empty, 'Enter')
    expect(screen.queryByLabelText('Item 5')).toBeNull()
    expect(kindsOf().slice(2, 5)).toEqual(['Checklist', 'Parágrafo', 'Bloco de código'])
  })

  it('Backspace num item vazio o remove e volta ao anterior; no único item, apaga o bloco', async () => {
    open()
    await keys(screen.getByLabelText('Item 4'), 'Enter')
    await keys(screen.getByLabelText('Item 5'), 'Backspace')
    expect(screen.queryByLabelText('Item 5')).toBeNull()
    await waitFor(() => expect(document.activeElement).toBe(screen.getByLabelText('Item 4')))

    await type(screen.getByLabelText('Nova linha'), '/')
    await click(screen.getByRole('menuitem', { name: /Checklist/ }))
    const solo = screen.getAllByLabelText('Item 1').at(-1)!
    await keys(solo, 'Backspace')
    expect(kindsOf()).not.toContain('Checklist 2')
    expect(blockEls().filter((b) => b.getAttribute('aria-label')!.startsWith('Checklist'))).toHaveLength(1)
  })
})

describe('Editor — código', () => {
  it('colore comentário, palavra-chave e texto; a linguagem muda a cor', async () => {
    open()
    const pre = document.querySelector('pre')!
    expect(pre.querySelector('.italic')!.textContent).toContain('# rotina noturna')
    expect(pre.textContent).toContain('def selar_trimestre')
    expect([...pre.querySelectorAll('span')].some((s) => s.textContent === 'def' && s.className.includes('text-tag-rust'))).toBe(true)
    await fireEvent.change(screen.getByLabelText('Linguagem do código'), { target: { value: 'texto' } })
    expect([...document.querySelector('pre')!.querySelectorAll('span')].some((s) => s.className.includes('text-tag-rust'))).toBe(false)
  })

  it('Tab indenta com quatro espaços e não tira o foco do campo', async () => {
    open()
    const area = screen.getByLabelText('Código') as HTMLTextAreaElement
    area.focus()
    caret(area, 0)
    const notCancelled = await keys(area, 'Tab')
    expect(notCancelled).toBe(false)
    expect(area.value.startsWith('    # rotina')).toBe(true)
  })

  it('digitar atualiza a cópia colorida por baixo (o que se vê é o que se digita)', async () => {
    open()
    await type(screen.getByLabelText('Código'), 'return 42')
    expect(document.querySelector('pre')!.textContent).toContain('return 42')
  })
})

describe('Editor — spoiler', () => {
  it('revela ao clicar, deixa editar e esconde de novo', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Revelar spoiler' }))
    const { inst } = await rich('Texto do spoiler')
    expect(plain(inst)).toContain('corte de 12%')
    await put(inst, 'novo segredo')
    await click(screen.getByRole('button', { name: 'ocultar' }))
    expect(document.body.textContent).not.toContain('novo segredo')
    await click(screen.getByRole('button', { name: 'Revelar spoiler' }))
    expect(drawn('Texto do spoiler').textContent).toBe('novo segredo')
  })

  it('o spoiler escondido não entra no resumo do cartão', () => {
    open()
    expect(ws.page('p0')!.excerpt).not.toContain('corte de 12%')
  })
})

describe('Editor — bloco seguro', () => {
  it('pede a senha: curta é recusada (e some do campo); certa revela e abre o cofre da sessão', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Ver bloco seguro' }))
    const input = screen.getByLabelText('Senha do cofre') as HTMLInputElement
    expect(input.type).toBe('password')
    await type(input, 'abc')
    await fireEvent.submit(input.closest('form')!)
    expect(screen.getByRole('alert').textContent).toContain('Senha incorreta')
    expect(input.value).toBe('')
    expect(document.body.textContent).not.toContain('PNDR-4471')

    await type(input, 'abcd')
    await fireEvent.submit(input.closest('form')!)
    expect((screen.getByLabelText('Texto do bloco seguro') as HTMLTextAreaElement).value).toContain('PNDR-4471')
    expect(ws.vaultUnlocked).toBe(true)
  })

  it('"ocultar novamente" esconde; com o cofre já aberto, "Ver" não pede senha outra vez', async () => {
    ws.unlockVault('abcd')
    open()
    await click(screen.getByRole('button', { name: 'Ver bloco seguro' }))
    expect(screen.queryByLabelText('Senha do cofre')).toBeNull()
    expect(screen.getByLabelText('Texto do bloco seguro')).toBeTruthy()
    await click(screen.getByRole('button', { name: 'ocultar novamente' }))
    expect(document.body.textContent).not.toContain('PNDR-4471')
  })

  it('Esc e Cancelar desistem sem revelar nada', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Ver bloco seguro' }))
    await keys(screen.getByLabelText('Senha do cofre'), 'Escape')
    expect(screen.queryByLabelText('Senha do cofre')).toBeNull()
    await click(screen.getByRole('button', { name: 'Ver bloco seguro' }))
    await click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.getByRole('button', { name: 'Ver bloco seguro' })).toBeTruthy()
    expect(ws.vaultUnlocked).toBe(false)
  })

  it('o segredo não entra no resumo do cartão nem na exportação', () => {
    open()
    expect(ws.page('p0')!.excerpt).not.toContain('PNDR')
  })
})

describe('Editor — tabela', () => {
  const cell = (r: number, c: number) => document.querySelector<HTMLInputElement>(`[data-cell="${r}-${c}"]`)!

  it('mostra cabeçalho e células e deixa editar', async () => {
    open()
    expect(cell(0, 0).value).toBe('Conciliação')
    await type(cell(0, 1), 'Ana')
    const t = ws.page('p0')!.content!.find((b) => b.type === 'table') as { rows: Record<string, string>[] }
    expect(t.rows[0].c2).toBe('Ana')
    await type(screen.getByLabelText('Nome da coluna 1'), 'Área')
    expect((screen.getByLabelText('Nome da coluna 1') as HTMLInputElement).value).toBe('Área')
  })

  it('adiciona e remove linha e coluna; sempre sobra ao menos uma de cada', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Adicionar linha' }))
    expect(document.querySelectorAll('tbody tr')).toHaveLength(4)
    await click(screen.getByRole('button', { name: 'Adicionar coluna' }))
    expect(document.querySelectorAll('thead th')).toHaveLength(6)
    await click(screen.getByRole('button', { name: 'Remover linha 4' }))
    expect(document.querySelectorAll('tbody tr')).toHaveLength(3)
    for (let i = 0; i < 6; i++) {
      const btn = screen.queryAllByRole('button', { name: /^Remover coluna/ })[0]
      if (btn) await click(btn)
    }
    expect(screen.queryAllByRole('button', { name: /^Remover coluna/ })).toHaveLength(0)
    expect(document.querySelectorAll('thead input')).toHaveLength(1)
  })

  it('a largura da coluna muda pelas setas na divisória e respeita o mínimo e o máximo', async () => {
    open()
    const sep = screen.getByRole('separator', { name: 'Largura da coluna Frente' })
    expect(sep.getAttribute('aria-valuenow')).toBe('250')
    await keys(sep, 'ArrowRight')
    expect(sep.getAttribute('aria-valuenow')).toBe('260')
    for (let i = 0; i < 100; i++) await keys(sep, 'ArrowLeft')
    expect(sep.getAttribute('aria-valuenow')).toBe('80')
    for (let i = 0; i < 100; i++) await keys(sep, 'ArrowRight')
    expect(sep.getAttribute('aria-valuenow')).toBe('600')
  })

  it('arrastar a divisória com o mouse muda a largura', async () => {
    open()
    const sep = screen.getByRole('separator', { name: 'Largura da coluna Responsável' })
    await fireEvent.pointerDown(sep, { clientX: 100 })
    window.dispatchEvent(Object.assign(new Event('pointermove'), { clientX: 140 }))
    await waitFor(() => expect(sep.getAttribute('aria-valuenow')).toBe('210'))
    window.dispatchEvent(new Event('pointerup'))
    window.dispatchEvent(Object.assign(new Event('pointermove'), { clientX: 400 }))
    expect(sep.getAttribute('aria-valuenow')).toBe('210') // released: no longer follows
  })

  it('Alt + seta na alça move a coluna e a linha', async () => {
    open()
    await keys(screen.getByRole('button', { name: 'Mover coluna Frente' }), 'ArrowRight', { altKey: true })
    expect([...document.querySelectorAll<HTMLInputElement>('thead input')].map((i) => i.value)).toEqual(['Responsável', 'Frente', 'Prazo'])
    expect(cell(0, 1).value).toBe('Conciliação')
    await keys(screen.getByRole('button', { name: 'Mover linha 1' }), 'ArrowDown', { altKey: true })
    expect(cell(1, 1).value).toBe('Conciliação')
    await keys(screen.getByRole('button', { name: 'Mover linha 1' }), 'ArrowUp', { altKey: true }) // already first: nothing
    expect(cell(1, 1).value).toBe('Conciliação')
  })

  it('arrastar uma linha para baixo da última a reordena', async () => {
    open()
    const dataTransfer = { effectAllowed: '', setData: vi.fn() }
    const rows = document.querySelectorAll('tbody tr')
    await fireEvent.dragStart(screen.getByRole('button', { name: 'Mover linha 1' }), { dataTransfer })
    await fireEvent.dragOver(rows[2], { dataTransfer })
    await fireEvent.drop(rows[2], { dataTransfer })
    expect(cell(0, 0).value).toBe('Contratos')
  })

  it('setas para cima e para baixo ficam na coluna; na última linha saem da tabela', async () => {
    open()
    cell(0, 1).focus()
    await keys(cell(0, 1), 'ArrowDown')
    expect(document.activeElement).toBe(cell(1, 1))
    await keys(cell(1, 1), 'ArrowUp')
    expect(document.activeElement).toBe(cell(0, 1))
    cell(2, 1).focus()
    caret(cell(2, 1), cell(2, 1).value.length)
    await keys(cell(2, 1), 'ArrowDown')
    expect(document.activeElement).toBe(screen.getByLabelText('Nova linha'))
  })
})

describe('Editor — imagem', () => {
  const addImage = async () => {
    await type(screen.getByLabelText('Nova linha'), '/')
    await click(screen.getByRole('menuitem', { name: /Imagem/ }))
  }

  it('aceita uma imagem, mostra com o nome como alt e permite remover', async () => {
    URL.createObjectURL = vi.fn(() => 'blob:img')
    URL.revokeObjectURL = vi.fn()
    open('p5')
    await addImage()
    const file = new File(['x'], 'foto.png', { type: 'image/png' })
    await fireEvent.change(screen.getByLabelText('Escolher imagem'), { target: { files: [file] } })
    expect((screen.getByAltText('foto.png') as HTMLImageElement).src).toBe('blob:img')
    await click(screen.getByRole('button', { name: 'remover' }))
    expect(screen.queryByAltText('foto.png')).toBeNull()
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:img')
  })

  it('recusa o que não é imagem e o que é grande demais', async () => {
    URL.createObjectURL = vi.fn(() => 'blob:x')
    open('p5')
    await addImage()
    const input = screen.getByLabelText('Escolher imagem')
    await fireEvent.change(input, { target: { files: [new File(['x'], 'a.svg', { type: 'image/svg+xml' })] } })
    expect(toast.message).toContain('PNG, JPEG')
    const big = new File(['x'], 'g.png', { type: 'image/png' })
    Object.defineProperty(big, 'size', { value: 9_000_000 })
    await fireEvent.change(input, { target: { files: [big] } })
    expect(toast.message).toContain('8 MB')
    expect(URL.createObjectURL).not.toHaveBeenCalled()
  })

  it('soltar um arquivo sobre a área também funciona', async () => {
    URL.createObjectURL = vi.fn(() => 'blob:drop')
    open('p5')
    await addImage()
    const zone = screen.getByText(/Arraste uma imagem/).closest('label')!
    await fireEvent.dragOver(zone)
    await fireEvent.drop(zone, { dataTransfer: { files: [new File(['x'], 'solta.webp', { type: 'image/webp' })] } })
    expect(screen.getByAltText('solta.webp')).toBeTruthy()
  })
})

describe('Editor — tags', () => {
  it('"+ tag" oferece as existentes; escolher adiciona, e a × remove', async () => {
    open()
    await click(screen.getByRole('button', { name: '+ tag' }))
    const existing = within(screen.getByRole('group', { name: 'Tags que já existem' }))
    expect(existing.queryByRole('button', { name: /operações/ })).toBeNull() // already on the page
    await click(existing.getByRole('button', { name: /leitura/ }))
    expect(ws.page('p0')!.tags).toContain('leitura')
    await click(screen.getByRole('button', { name: 'Remover tag leitura' }))
    expect(ws.page('p0')!.tags).not.toContain('leitura')
  })

  it('cria uma tag nova com a cor escolhida; nome vazio só fecha', async () => {
    open()
    await click(screen.getByRole('button', { name: '+ tag' }))
    await click(screen.getByRole('button', { name: 'Cor dourado' }))
    const input = screen.getByLabelText('Nome da nova tag')
    await type(input, 'Revisão final')
    await fireEvent.submit(input.closest('form')!)
    expect(ws.tag('revisao-final')).toMatchObject({ name: 'revisão-final', color: 'gold' })
    expect(screen.queryByLabelText('Nome da nova tag')).toBeNull()
    await click(screen.getByRole('button', { name: '+ tag' }))
    await fireEvent.submit(screen.getByLabelText('Nome da nova tag').closest('form')!)
    expect(screen.queryByLabelText('Nome da nova tag')).toBeNull()
  })

  it('uma tag repetida não duplica e Esc fecha o formulário', async () => {
    open()
    await click(screen.getByRole('button', { name: '+ tag' }))
    const input = screen.getByLabelText('Nome da nova tag')
    await type(input, 'trimestral')
    await fireEvent.submit(input.closest('form')!)
    expect(ws.page('p0')!.tags.filter((t) => t === 'trimestral')).toHaveLength(1)
    await keys(screen.getByLabelText('Nome da nova tag'), 'Escape')
    expect(screen.queryByLabelText('Nome da nova tag')).toBeNull()
  })
})

describe('Editor — página no cofre e na lixeira', () => {
  it('uma página do cofre só abre depois da senha mestra', async () => {
    open('p4')
    expect(screen.queryByLabelText('Parágrafo')).toBeNull()
    expect(document.body.textContent).not.toContain('Conteúdo protegido')
    await click(screen.getByRole('button', { name: 'Desbloquear' }))
    const input = screen.getByLabelText('Senha mestra', { selector: 'input' })
    await type(input, 'ab')
    await fireEvent.submit(input.closest('form')!)
    expect(screen.getByRole('alert').textContent).toContain('mínimo 4')
    await type(input, 'abcd')
    await fireEvent.submit(input.closest('form')!)
    await waitFor(() => expect(screen.getByLabelText('Parágrafo')).toBeTruthy())
  })

  it('página na lixeira fica só para ler, com aviso e botão de restaurar', async () => {
    ws.trash('p0')
    open()
    expect(screen.getByText(/está na lixeira/)).toBeTruthy()
    expect((screen.getByLabelText('Título da página') as HTMLTextAreaElement).readOnly).toBe(true)
    expect(screen.queryByLabelText('Nova linha')).toBeNull()
    expect(screen.queryByRole('button', { name: /Inserir bloco depois/ })).toBeNull()
    expect(screen.queryByRole('button', { name: '+ tag' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Adicionar linha' })).toBeNull()
    // the text can be read and selected but focusing it opens no editor
    drawn().focus()
    await tick()
    noEditor()
    expect(document.body.textContent).not.toContain('não deve entrar')
    await click(screen.getByRole('button', { name: 'Restaurar' }))
    expect(ws.page('p0')!.trashed).toBe(false)
    await rich()
  })
})

describe('Editor — celular e acessibilidade', () => {
  it('apertar a alça de arrastar não cancela o início do arrastar do navegador', async () => {
    open()
    const handle = screen.getAllByRole('button', { name: /Opções de/ })[0]
    // a cancelled mousedown keeps the browser from starting a drag: it must go through
    expect(await fireEvent.mouseDown(handle)).toBe(true)
    expect(handle.getAttribute('draggable')).toBe('true')
    const insert = screen.getAllByRole('button', { name: /Inserir bloco depois/ })[0]
    expect(await fireEvent.mouseDown(insert)).toBe(true)
  })

  it('no celular não reserva coluna lateral: as alças ficam sob o bloco tocado, só nele', async () => {
    viewport.set(390)
    open()
    expect(blockEls()[0].className).not.toContain('pl-16')
    const row = (i: number) => blockEls()[i]
    const controls = (i: number) => row(i).querySelector('button[data-insert-trigger]')!.parentElement!
    expect(controls(0).className).toContain('max-md:hidden')
    expect(controls(1).className).toContain('max-md:hidden')
    await click(row(0).querySelector('textarea, [contenteditable], div')!)
    expect(controls(0).className).not.toContain('max-md:hidden')
    expect(controls(1).className).toContain('max-md:hidden')
    // touching another block moves them; touching outside hides them
    const second = row(1).querySelector<HTMLElement>('textarea, [contenteditable], div')!
    await fireEvent.pointerDown(second)
    await click(second)
    expect(controls(0).className).toContain('max-md:hidden')
    expect(controls(1).className).not.toContain('max-md:hidden')
    await fireEvent.pointerDown(document.body)
    expect(controls(1).className).toContain('max-md:hidden')
  })

  it('o menu de opções continua aberto e a alça visível enquanto ele estiver aberto', async () => {
    viewport.set(390)
    open()
    const row = blockEls()[0]
    await click(row.querySelector('textarea, [contenteditable], div')!)
    await click(within(row).getByRole('button', { name: /Opções de/ }))
    expect(within(row).getByRole('menu')).toBeTruthy()
    expect(row.querySelector('button[data-insert-trigger]')!.parentElement!.className).not.toContain('max-md:hidden')
  })

  it('axe: página inteira, menu de inserir, tabela com cabeçalhos e bloco seguro pedindo senha', async () => {
    open()
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    expect(await violations()).toEqual([])
    await keys(screen.getAllByRole('menuitem')[0], 'Escape')
    await click(screen.getByRole('button', { name: 'Ver bloco seguro' }))
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: 'Opções de Título de seção 1' }))
    expect(await violations()).toEqual([])
  })

  it('axe: página na lixeira, página do cofre trancada e tags abertas', async () => {
    ws.trash('p0')
    const { unmount } = open()
    expect(await violations()).toEqual([])
    unmount()
    open('p4')
    expect(await violations()).toEqual([])
  })

  it('axe: celular', async () => {
    viewport.set(390)
    open()
    expect(await violations()).toEqual([])
  })
})

// ---------------------------------------------------------------------------------------------------------------------
// Excluir, exportar, compartilhar e permissões
// ---------------------------------------------------------------------------------------------------------------------

function captureDownload() {
  const blobs: Blob[] = []
  const names: string[] = []
  URL.createObjectURL = vi.fn((b: Blob) => (blobs.push(b), 'blob:x'))
  URL.revokeObjectURL = vi.fn()
  const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
    names.push(this.download)
  })
  const text = (b: Blob) =>
    new Promise<string>((resolve) => {
      const r = new FileReader()
      r.onload = () => resolve(String(r.result))
      r.readAsText(b)
    })
  return { blobs, names, text, restore: () => click.mockRestore() }
}

describe('Editor — excluir a página', () => {
  it('o botão fica na própria página; pede confirmação com o "Cancelar" já em foco', async () => {
    const onback = vi.fn()
    open('p0', onback)
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    const dialog = screen.getByRole('alertdialog')
    expect(within(dialog).getByRole('heading', { name: 'Mover para a lixeira?' })).toBeTruthy()
    expect(document.activeElement).toBe(within(dialog).getByRole('button', { name: 'Cancelar' }))
    await click(within(dialog).getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('alertdialog')).toBeNull()
    expect(ws.page('p0')!.trashed).toBe(false)
    expect(onback).not.toHaveBeenCalled()
  })

  it('Esc e o fundo cancelam', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    await keys(window, 'Escape')
    expect(screen.queryByRole('alertdialog')).toBeNull()
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    await click(screen.getByTestId('confirm-backdrop'))
    expect(screen.queryByRole('alertdialog')).toBeNull()
    expect(ws.page('p0')).toBeTruthy()
  })

  it('confirmar manda para a lixeira e volta ao painel', async () => {
    const onback = vi.fn()
    open('p0', onback)
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    await click(screen.getByRole('button', { name: 'Mover para a lixeira' }))
    expect(ws.page('p0')!.trashed).toBe(true)
    expect(toast.message).toBe('Movida para a lixeira')
    expect(onback).toHaveBeenCalledOnce()
  })

  it('com a lixeira desligada, apaga de vez e avisa que não dá para desfazer', async () => {
    ws.saveSettings({ useTrash: false, retention: 30 })
    const onback = vi.fn()
    open('p0', onback)
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    expect(screen.getByRole('alertdialog').textContent).toContain('não pode ser desfeito')
    await click(screen.getByRole('button', { name: 'Excluir definitivamente' }))
    expect(ws.page('p0')).toBeUndefined()
    expect(onback).toHaveBeenCalled()
  })

  it('uma página do cofre sempre some de vez', async () => {
    ws.unlockVault('abcd')
    open('v2')
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    await click(screen.getByRole('button', { name: 'Excluir definitivamente' }))
    expect(ws.page('v2')).toBeUndefined()
    expect(ws.counts.trash).toBe(0)
  })

  it('na lixeira o botão é "Excluir definitivamente"', async () => {
    ws.trash('p0')
    const onback = vi.fn()
    open('p0', onback)
    await click(screen.getByRole('button', { name: 'Excluir página definitivamente' }))
    await click(screen.getByRole('button', { name: 'Excluir definitivamente' }))
    expect(ws.page('p0')).toBeUndefined()
    expect(onback).toHaveBeenCalled()
  })

  it('numa página que recebi, sai só da minha lista e o texto diz quem continua com ela', async () => {
    open('s1')
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    expect(screen.getByRole('alertdialog').textContent).toContain('Caio')
    await click(screen.getByRole('button', { name: 'Excluir definitivamente' }))
    expect(ws.page('s1')).toBeUndefined()
  })

  it('sem a permissão de excluir o botão nem aparece', () => {
    open('s3')
    expect(screen.queryByRole('button', { name: /Excluir página/ })).toBeNull()
  })
})

describe('Editor — exportar a página', () => {
  it('o menu oferece Markdown, HTML, texto, JSON e copiar', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    const menu = within(screen.getByRole('menu', { name: 'Exportar página' }))
    expect(menu.getAllByRole('menuitem').map((m) => m.textContent!.replace(/\s+/g, ' ').trim())).toEqual([
      'Markdown.md',
      'HTML.html',
      'Texto simples.txt',
      'JSON.json',
      'Copiar como Markdown',
    ])
  })

  it('baixa o arquivo com nome seguro e o conteúdo da página, sem o bloco seguro', async () => {
    const cap = captureDownload()
    open()
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    await click(screen.getByRole('menuitem', { name: /^Markdown/ }))
    expect(cap.names).toEqual(['Rotina-de-encerramento-do-trimestre.md'])
    const body = await cap.text(cap.blobs[0])
    expect(body).toContain('# Rotina de encerramento do trimestre')
    expect(body).toContain('- [x] Fechar conciliação')
    expect(body).not.toContain('PNDR-4471')
    expect(toast.message).toBe('Exportada como Markdown')
    expect(screen.queryByRole('menu', { name: 'Exportar página' })).toBeNull()
    cap.restore()
  })

  it('cada formato gera a extensão certa', async () => {
    const cap = captureDownload()
    open()
    for (const [name, ext] of [[/HTML/, 'html'], [/Texto simples/, 'txt'], [/JSON/, 'json']] as const) {
      await click(screen.getByRole('button', { name: 'Exportar página' }))
      await click(screen.getByRole('menuitem', { name }))
      expect(cap.names.at(-1)).toMatch(new RegExp(`\\.${ext}$`))
    }
    cap.restore()
  })

  it('o bloco seguro só entra com o cofre aberto e a caixa marcada', async () => {
    const cap = captureDownload()
    open()
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    expect(screen.getByText(/1 bloco seguro fica de fora/)).toBeTruthy()
    expect(screen.queryByLabelText(/Incluir o bloco seguro/)).toBeNull()
    await keys(window, 'Escape')

    ws.unlockVault('abcd')
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    await click(screen.getByLabelText(/Incluir o bloco seguro/))
    await click(screen.getByRole('menuitem', { name: /^Markdown/ }))
    expect(await cap.text(cap.blobs[0])).toContain('PNDR-4471')
    cap.restore()
  })

  it('copia o Markdown; sem acesso à área de transferência avisa', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.assign(navigator, { clipboard: { writeText } })
    open()
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    await click(screen.getByRole('menuitem', { name: 'Copiar como Markdown' }))
    await waitFor(() => expect(toast.message).toBe('Markdown copiado'))
    expect(writeText.mock.calls[0][0]).toContain('# Rotina de encerramento')

    writeText.mockRejectedValue(new Error('negado'))
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    await click(screen.getByRole('menuitem', { name: 'Copiar como Markdown' }))
    await waitFor(() => expect(toast.message).toBe('Não foi possível copiar'))
  })

  it('se o navegador não deixa baixar, avisa; Esc e clicar fora fecham o menu', async () => {
    URL.createObjectURL = vi.fn(() => {
      throw new Error('no')
    })
    open()
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    await click(screen.getByRole('menuitem', { name: /^Markdown/ }))
    expect(toast.message).toBe('Não foi possível exportar')
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    await keys(window, 'Escape')
    expect(screen.queryByRole('menu', { name: 'Exportar página' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Exportar página' }))
    await fireEvent.mouseDown(document.body)
    expect(screen.queryByRole('menu', { name: 'Exportar página' })).toBeNull()
  })

  it('sem a permissão de exportar o botão não aparece; na lixeira ainda dá para exportar', () => {
    open('s2')
    expect(screen.queryByRole('button', { name: 'Exportar página' })).toBeNull()
    ws.trash('p0')
    open('p0')
    expect(screen.getByRole('button', { name: 'Exportar página' })).toBeTruthy()
  })
})

describe('Editor — com quem a página foi compartilhada', () => {
  it('mostra as pessoas, o acesso de cada uma e as duas ações', () => {
    open()
    const bar = within(screen.getByRole('group', { name: 'Compartilhamento' }))
    expect(bar.getByText('Compartilhada com')).toBeTruthy()
    const people = within(bar.getByRole('list', { name: 'Pessoas com acesso' }))
    expect(people.getByText('Caio')).toBeTruthy()
    expect(people.getByText('Editar tudo')).toBeTruthy() // read by screen readers
    expect(people.getByText('Somente leitura')).toBeTruthy()
    expect(bar.getByRole('button', { name: /Compartilhar/ })).toBeTruthy()
    expect(bar.getByRole('button', { name: /Retirar acesso/ })).toBeTruthy()
  })

  it('uma página não compartilhada diz isso e só oferece compartilhar', () => {
    open('p1')
    const bar = within(screen.getByRole('group', { name: 'Compartilhamento' }))
    expect(bar.getByText('Não compartilhada')).toBeTruthy()
    expect(bar.queryByRole('button', { name: /Retirar acesso/ })).toBeNull()
    expect(bar.getByRole('button', { name: /Compartilhar/ })).toBeTruthy()
  })

  it('com muita gente mostra quatro e conta o resto', () => {
    ws.sharePage('p1', ['caio', 'julia', 'rafa', 'ruy', 'bea', 'tiago'], [])
    open('p1')
    expect(within(screen.getByRole('list', { name: 'Pessoas com acesso' })).getAllByRole('listitem')).toHaveLength(5)
    expect(screen.getByText('+2')).toBeTruthy()
  })

  it('numa página que recebi mostra quem compartilhou e o que posso; só compartilha se a permissão deixar', () => {
    open('s1')
    expect(screen.getByText('Caio', { selector: 'strong' })).toBeTruthy()
    expect(screen.getByText('você pode: editar tudo')).toBeTruthy()
    expect(screen.getByRole('button', { name: /Compartilhar/ })).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Retirar acesso/ })).toBeNull() // only the owner takes access away
  })

  it('sem a permissão de compartilhar não há botão', () => {
    open('s3')
    expect(screen.getByText(/você pode: personalizado/)).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Compartilhar/ })).toBeNull()
  })
})

describe('Editor — modal de compartilhamento', () => {
  const openShare = async (id = 'p0', name: RegExp = /Retirar acesso/) => {
    open(id)
    await click(screen.getByRole('button', { name }))
    return within(screen.getByRole('dialog', { name: 'Compartilhar' }))
  }

  it('"Retirar acesso…" abre em "Com acesso"; "Compartilhar" abre em "Adicionar pessoas"', async () => {
    const dialog = await openShare()
    expect(dialog.getByRole('tab', { name: /Com acesso/ }).getAttribute('aria-selected')).toBe('true')
    expect(dialog.getByText('Caio Mendes')).toBeTruthy()
    expect(dialog.getByText('@caio · caio@pindrel.local')).toBeTruthy()
    await click(dialog.getByRole('button', { name: 'Fechar' }))
    await click(screen.getByRole('button', { name: /^Compartilhar/ }))
    const again = within(screen.getByRole('dialog', { name: 'Compartilhar' }))
    expect(again.getByRole('tab', { name: 'Adicionar pessoas' }).getAttribute('aria-selected')).toBe('true')
    expect(document.activeElement).toBe(again.getByRole('searchbox'))
  })

  it('retira o acesso de uma pessoa só', async () => {
    const dialog = await openShare()
    await click(dialog.getByRole('button', { name: 'Retirar acesso de Júlia Prado' }))
    expect(ws.page('p0')!.shares.map((s) => s.userId)).toEqual(['caio'])
    expect(toast.message).toBe('Acesso de Júlia Prado retirado')
    expect(dialog.queryByText('Júlia Prado')).toBeNull()
    expect(within(screen.getByRole('group', { name: 'Compartilhamento' })).queryByText('Júlia')).toBeNull()
  })

  it('"Retirar de todos" pede uma segunda confirmação e dá para desistir', async () => {
    const dialog = await openShare()
    await click(dialog.getByRole('button', { name: 'Retirar de todos' }))
    expect(ws.page('p0')!.shares).toHaveLength(2) // the first click only asks
    await click(dialog.getByRole('button', { name: 'Cancelar' }))
    expect(dialog.getByRole('button', { name: 'Retirar de todos' })).toBeTruthy()
    await click(dialog.getByRole('button', { name: 'Retirar de todos' }))
    await click(dialog.getByRole('button', { name: /Confirmar: retirar de todos \(2\)/ }))
    expect(ws.page('p0')!.shares).toEqual([])
    expect(toast.message).toBe('Compartilhamento retirado de todos')
    expect(dialog.getByTestId('no-shares')).toBeTruthy()
  })

  it('muda o acesso de alguém: nível pronto e ajuste fino em "Avançado"', async () => {
    const dialog = await openShare()
    await click(dialog.getByRole('button', { name: 'Permissões de Júlia Prado' }))
    const radios = dialog.getAllByRole('radio') as HTMLInputElement[]
    expect(radios.find((r) => r.value === 'read')!.checked).toBe(true)
    await click(dialog.getByRole('radio', { name: /Editar tudo/ }))
    expect(ws.page('p0')!.shares.find((s) => s.userId === 'julia')!.perms).toHaveLength(10)
    // every box is checked while "Editar tudo" is selected
    expect(dialog.getAllByRole('checkbox').every((c) => (c as HTMLInputElement).checked)).toBe(true)
    await click(dialog.getByRole('checkbox', { name: /Compartilhar com outras pessoas/ }))
    expect(ws.page('p0')!.shares.find((s) => s.userId === 'julia')!.perms).not.toContain('share')
    expect(dialog.getByRole('radio', { name: /Personalizado \(9 de 10\)/ })).toBeTruthy()
    // the others stay as they were
    expect(ws.page('p0')!.shares.find((s) => s.userId === 'caio')!.perms).toHaveLength(10)
  })

  it('o "Avançado" lista o que dá para tirar: compartilhar, tags, imagens e o resto', async () => {
    const dialog = await openShare()
    await click(dialog.getByRole('button', { name: 'Permissões de Caio Mendes' }))
    const boxes = dialog.getAllByRole('checkbox').map((c) => c.closest('label')!.textContent!.replace(/\s+/g, ' '))
    for (const label of ['Compartilhar com outras pessoas', 'Adicionar e remover tags', 'Adicionar imagens', 'Excluir a página', 'Exportar a página', 'Editar textos e títulos', 'Alterar linhas e colunas de tabelas']) {
      expect(boxes.some((b) => b.includes(label))).toBe(true)
    }
  })

  describe('adicionar pessoas', () => {
    const openAdd = async () => {
      open('p0')
      await click(screen.getByRole('button', { name: /^Compartilhar/ }))
      return within(screen.getByRole('dialog', { name: 'Compartilhar' }))
    }

    it('lista todos os usuários do servidor que ainda não têm acesso (nem você)', async () => {
      const dialog = await openAdd()
      const list = within(dialog.getByRole('list', { name: 'Usuários do servidor' }))
      expect(list.getAllByRole('listitem')).toHaveLength(6) // 9 users - me - caio - julia
      expect(list.queryByText('Marina Reis')).toBeNull()
      expect(list.queryByText('Caio Mendes')).toBeNull()
      expect(dialog.getByRole('status').textContent).toBe('6 usuários do servidor')
    })

    it('busca por e-mail ou por username (e também pelo nome)', async () => {
      const dialog = await openAdd()
      const search = dialog.getByRole('searchbox')
      const shown = () => within(dialog.getByRole('list', { name: 'Usuários do servidor' })).getAllByRole('listitem').map((li) => li.textContent!.replace(/\s+/g, ' ').trim())
      await type(search, 'familia.casa')
      expect(shown()).toHaveLength(2)
      expect(dialog.getByRole('status').textContent).toBe('2 resultados')
      await type(search, 'tiagof')
      expect(shown()).toEqual([expect.stringContaining('Tiago Ferraz')])
      expect(dialog.getByRole('status').textContent).toBe('1 resultado')
      await type(search, '@helena')
      expect(shown()).toEqual([expect.stringContaining('Helena Costa')])
      await type(search, 'otávio')
      expect(shown()).toHaveLength(1)
      await type(search, 'ninguém aqui')
      expect(dialog.getByTestId('no-users').textContent).toContain('Nenhum usuário encontrado')
      await type(search, '')
      expect(shown()).toHaveLength(6)
    })

    it('escolher várias pessoas e o acesso: começa em "Somente leitura", muda para "Editar tudo"', async () => {
      const dialog = await openAdd()
      const submit = dialog.getByRole('button', { name: 'Escolha quem recebe' }) as HTMLButtonElement
      expect(submit.disabled).toBe(true)
      expect((dialog.getByRole('radio', { name: /Somente leitura/ }) as HTMLInputElement).checked).toBe(true)
      await click(dialog.getByRole('checkbox', { name: 'Selecionar Tiago Ferraz' }))
      await click(dialog.getByRole('checkbox', { name: 'Selecionar Beatriz Lima' }))
      await click(dialog.getByRole('radio', { name: /Editar tudo/ }))
      await click(dialog.getByRole('checkbox', { name: /Excluir a página/ })) // take one thing away
      await click(dialog.getByRole('button', { name: 'Compartilhar com 2 pessoas' }))

      const added = ws.page('p0')!.shares.filter((s) => ['tiago', 'bea'].includes(s.userId))
      expect(added).toHaveLength(2)
      for (const s of added) {
        expect(s.perms).toHaveLength(9)
        expect(s.perms).not.toContain('delete')
      }
      expect(toast.message).toBe('Compartilhada com 2 pessoas')
      // back to the list of people with access, now with them
      expect(dialog.getByRole('tab', { name: /Com acesso/ }).getAttribute('aria-selected')).toBe('true')
      expect(dialog.getByText('Tiago Ferraz')).toBeTruthy()
    })

    it('uma pessoa só, com acesso de leitura', async () => {
      const dialog = await openAdd()
      await click(dialog.getByRole('checkbox', { name: 'Selecionar Rafael Souza' }))
      await click(dialog.getByRole('button', { name: 'Compartilhar com 1 pessoa' }))
      expect(ws.page('p0')!.shares.find((s) => s.userId === 'rafa')!.perms).toEqual([])
      expect(toast.message).toBe('Compartilhada com 1 pessoa')
    })

    it('desmarcar tira a pessoa da escolha; a seleção sobrevive à busca', async () => {
      const dialog = await openAdd()
      await click(dialog.getByRole('checkbox', { name: 'Selecionar Tiago Ferraz' }))
      await type(dialog.getByRole('searchbox'), 'helena')
      await click(dialog.getByRole('checkbox', { name: 'Selecionar Helena Costa' }))
      expect(dialog.getByRole('button', { name: 'Compartilhar com 2 pessoas' })).toBeTruthy()
      await click(dialog.getByRole('checkbox', { name: 'Selecionar Helena Costa' }))
      expect(dialog.getByRole('button', { name: 'Compartilhar com 1 pessoa' })).toBeTruthy()
    })

    it('quando todos já têm acesso diz isso', async () => {
      ws.sharePage('p0', ws.users.map((u) => u.id), [])
      const dialog = await openAdd()
      expect(dialog.getByTestId('no-users').textContent).toContain('Todos os usuários do servidor já têm acesso')
    })

    it('na aba "Com acesso" sem ninguém, oferece adicionar', async () => {
      open('p1')
      await click(screen.getByRole('button', { name: /^Compartilhar/ }))
      const dialog = within(screen.getByRole('dialog', { name: 'Compartilhar' }))
      await click(dialog.getByRole('tab', { name: /Com acesso/ }))
      await click(dialog.getByRole('button', { name: 'Adicionar pessoas' }))
      expect(dialog.getByRole('searchbox')).toBeTruthy()
    })
  })

  it('quem recebeu a página com permissão de compartilhar só adiciona, não retira', async () => {
    ws.page('s3')!.myPerms = ['share']
    ws.sharePage('s3', ['tiago'], [])
    open('s3')
    await click(screen.getByRole('button', { name: /^Compartilhar/ }))
    const dialog = within(screen.getByRole('dialog', { name: 'Compartilhar' }))
    await click(dialog.getByRole('tab', { name: /Com acesso/ }))
    expect(dialog.queryByRole('button', { name: /Retirar/ })).toBeNull()
    expect(dialog.getByText(/Só quem criou a página pode retirar/)).toBeTruthy()
  })

  it('Esc e o fundo fecham o modal', async () => {
    await openShare()
    await keys(window, 'Escape')
    expect(screen.queryByRole('dialog', { name: 'Compartilhar' })).toBeNull()
    await click(screen.getByRole('button', { name: /Retirar acesso/ }))
    await click(screen.getByTestId('share-backdrop'))
    expect(screen.queryByRole('dialog', { name: 'Compartilhar' })).toBeNull()
  })

  it('axe: aba com acesso, permissões abertas, adicionar e o diálogo de excluir', async () => {
    const dialog = await openShare()
    expect(await violations()).toEqual([])
    await click(dialog.getByRole('button', { name: 'Permissões de Caio Mendes' }))
    expect(await violations()).toEqual([])
    await click(dialog.getByRole('tab', { name: 'Adicionar pessoas' }))
    expect(await violations()).toEqual([])
    await keys(window, 'Escape')
    await click(screen.getByRole('button', { name: 'Excluir página' }))
    expect(await violations()).toEqual([])
  })

  it('no celular o modal sobe pela base e cabe na tela', async () => {
    viewport.set(390)
    open()
    await click(screen.getByRole('button', { name: 'Abrir propriedades' }))
    await click(screen.getByRole('button', { name: /Retirar acesso/ }))
    const dialog = within(screen.getByRole('dialog', { name: 'Compartilhar' }))
    expect(dialog.getByText('Caio Mendes')).toBeTruthy()
    expect(screen.getByRole('dialog').className).toContain('rounded-t-3xl')
  })
})

describe('Editor — o que cada permissão libera na tela', () => {
  it('só leitura: nada editável, sem alças, sem linha nova, sem tags, sem excluir nem exportar', async () => {
    open('s2')
    expect((screen.getByLabelText('Título da página') as HTMLTextAreaElement).readOnly).toBe(true)
    drawn().focus()
    await tick()
    noEditor()
    expect(screen.queryByLabelText('Nova linha')).toBeNull()
    expect(screen.queryByRole('button', { name: /Inserir bloco depois/ })).toBeNull()
    expect(screen.queryByRole('button', { name: '+ tag' })).toBeNull()
    expect(screen.queryByRole('button', { name: /Excluir/ })).toBeNull()
    expect(screen.queryByRole('button', { name: /Exportar/ })).toBeNull()
    expect(screen.queryByRole('button', { name: /Compartilhar/ })).toBeNull()
  })

  it('só leitura: tentar escrever não muda a página', async () => {
    open('s2')
    const before = (ws.page('s2')!.content![0] as { text: string }).text
    drawn().focus()
    await tick()
    noEditor()
    await keys(drawn(), 'x')
    expect((ws.page('s2')!.content![0] as { text: string }).text).toBe(before)
  })

  it('permissões personalizadas: edita o texto mas não cria imagem, não mexe em tags, não exclui', async () => {
    open('s3')
    const { inst } = await rich()
    await put(inst, 'editado')
    expect((ws.page('s3')!.content![0] as { text: string }).text).toBe('editado')
    expect(screen.queryByRole('button', { name: '+ tag' })).toBeNull()
    expect(screen.queryByRole('button', { name: /Excluir página/ })).toBeNull()
    expect(screen.getByRole('button', { name: 'Exportar página' })).toBeTruthy()
    await type(screen.getByLabelText('Nova linha'), '/')
    expect((screen.getByRole('menuitem', { name: /Imagem/ }) as HTMLButtonElement).disabled).toBe(true)
    expect((screen.getByRole('menuitem', { name: /Texto/ }) as HTMLButtonElement).disabled).toBe(false)
  })

  it('sem "ver blocos seguros" o botão Ver não existe', () => {
    ws.page('s3')!.content = [{ id: 'sec', type: 'secure', text: 'segredo' }]
    ws.page('s3')!.myPerms = ['text']
    open('s3')
    expect(screen.queryByRole('button', { name: 'Ver bloco seguro' })).toBeNull()
    expect(screen.getByText('sem permissão para ver este bloco')).toBeTruthy()
    expect(document.body.textContent).not.toContain('segredo')
  })

  it('sem "marcar checklist" os itens ficam travados; sem "tabelas" a tabela não muda de forma', () => {
    ws.page('s3')!.content = [
      { id: 'c', type: 'checklist', items: [{ id: 'i', text: 'a', done: false }] },
      { id: 't', type: 'table', cols: [{ id: 'k', label: 'K', w: 100 }], rows: [{ k: 'v' }] },
    ]
    ws.page('s3')!.myPerms = ['text']
    open('s3')
    expect((screen.getByRole('checkbox') as HTMLButtonElement).disabled).toBe(true)
    expect(screen.queryByRole('button', { name: 'Adicionar linha' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Adicionar coluna' })).toBeNull()
    expect(screen.queryByRole('separator', { name: /Largura/ })).toBeNull()
  })

  it('axe: página de só leitura e página com permissões personalizadas', async () => {
    const { unmount } = open('s2')
    expect(await violations()).toEqual([])
    unmount()
    open('s3')
    expect(await violations()).toEqual([])
  })
})

describe('Editor — cabeçalho no celular', () => {
  it('no celular o cabeçalho tem só voltar, exportar e "Mais ações", todos com nome acessível', async () => {
    viewport.set(390)
    open()
    expect(screen.getByRole('button', { name: 'Exportar página' })).toBeTruthy()
    expect(screen.getByRole('button', { name: /Dashboard/ })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Modo zen' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Excluir página' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    expect(within(screen.getByRole('menu', { name: 'Mais ações' })).getAllByRole('menuitem').map((m) => m.textContent!.trim())).toEqual(['Modo zen', 'Excluir página'])
  })
})

// ---------------------------------------------------------------------------------------------------------------------
// Painel lateral e páginas vazias
// ---------------------------------------------------------------------------------------------------------------------

describe('Editor — painel lateral', () => {
  beforeEach(() => {
    stubLocalStorage()
  })
  const panel = () => within(screen.getByRole('complementary', { name: 'Painel da página' }))

  it('numa tela larga o painel já vem aberto, ao lado da página', () => {
    open()
    expect(screen.getByRole('button', { name: 'Fechar painel' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Painel da página' })).toBeNull()
    expect(panel().getByRole('heading', { name: 'Nesta página' })).toBeTruthy()
    expect(panel().getByRole('heading', { name: 'Detalhes' })).toBeTruthy()
    expect(panel().getByRole('heading', { name: 'Relacionadas' })).toBeTruthy()
    expect(panel().getByRole('heading', { name: 'Ações' })).toBeTruthy()
  })

  it('a seta fecha e abre, e a escolha fica lembrada', async () => {
    const { unmount } = open()
    await click(screen.getByRole('button', { name: 'Fechar painel' }))
    expect(screen.queryByRole('complementary', { name: 'Painel da página' })).toBeNull()
    expect(localStorage.getItem('pindrel:editor-panel')).toBe('0')
    unmount()
    open()
    expect(screen.queryByRole('complementary', { name: 'Painel da página' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Abrir painel' }))
    expect(localStorage.getItem('pindrel:editor-panel')).toBe('1')
    expect(panel().getByRole('heading', { name: 'Detalhes' })).toBeTruthy()
  })

  it('sem acesso ao armazenamento do navegador o painel ainda abre e fecha', async () => {
    const spy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('cheio')
    })
    open()
    await click(screen.getByRole('button', { name: 'Fechar painel' }))
    expect(screen.queryByRole('complementary', { name: 'Painel da página' })).toBeNull()
    spy.mockRestore()
  })

  it('o sumário lista os títulos de seção e clicar leva até eles', async () => {
    const scroll = vi.fn()
    Element.prototype.scrollIntoView = scroll
    open()
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    await click(screen.getByRole('menuitem', { name: /^Título 2$/ }))
    const links = within(panel().getAllByRole('list')[0]).getAllByRole('button')
    expect(links.map((l) => l.textContent!.trim())).toEqual(['O que precisa acontecer antes do dia 31', 'Sem título'])
    scroll.mockClear()
    await click(links[0])
    expect(scroll).toHaveBeenCalledOnce()
    expect((scroll.mock.instances[0] as HTMLElement).dataset.blockId).toBe('r1')
  })

  it('sem títulos explica o que aparece ali', () => {
    open('p5')
    expect(panel().getByTestId('no-outline')).toBeTruthy()
  })

  it('os detalhes mostram palavras, leitura e blocos, e acompanham o que se escreve', async () => {
    open('p5')
    const words = Number(panel().getByTestId('stat-words').textContent)
    expect(words).toBeGreaterThan(10)
    expect(panel().getByTestId('stat-read').textContent).toBe('1 min')
    const { inst } = await rich()
    await put(inst, 'só três palavras')
    expect(panel().getByTestId('stat-words').textContent).toBe('3')
    await put(inst, '')
    expect(panel().getByTestId('stat-words').textContent).toBe('0')
    expect(panel().getByTestId('stat-read').textContent).toBe('—')
  })

  it('a barra de progresso das checklists segue as marcações', async () => {
    open()
    const bar = panel().getByRole('progressbar', { name: 'Itens concluídos' })
    expect(bar.getAttribute('aria-valuenow')).toBe('2')
    expect(bar.getAttribute('aria-valuemax')).toBe('4')
    expect((bar.firstElementChild as HTMLElement).style.width).toBe('50%')
    await click(screen.getByRole('checkbox', { name: /Rodar o export/ }))
    expect(bar.getAttribute('aria-valuenow')).toBe('3')
    expect((bar.firstElementChild as HTMLElement).style.width).toBe('75%')
  })

  it('sem checklist a barra nem aparece; o bloco seguro não entra na contagem de palavras', () => {
    open('p5')
    expect(panel().queryByRole('progressbar')).toBeNull()
    ws.page('p5')!.content!.push({ id: 's', type: 'secure', text: 'palavras que não contam nada aqui' })
    const words = Number(panel().getByTestId('stat-words').textContent)
    expect(words).toBe(Number(panel().getByTestId('stat-words').textContent))
    expect(document.body.textContent).not.toContain('palavras que não contam')
  })

  it('páginas relacionadas: as que dividem tags, clicáveis; sem tags ou sem parecidas, diz isso', async () => {
    const onopen = vi.fn()
    render(Editor, { ws, id: 'p0', onback: vi.fn(), onopen })
    expect(panel().queryByTestId('no-related')).toBeNull()
    await click(panel().getByRole('button', { name: /Notas da reunião de produto/ }))
    expect(onopen).toHaveBeenCalledWith('p3')
  })

  it('sem tags: avisa; com tags que ninguém mais usa: avisa de outro jeito', async () => {
    open('p1')
    expect(panel().queryByTestId('no-related')).toBeNull()
    ws.page('p1')!.tags = []
    await waitFor(() => expect(panel().getByTestId('no-related').textContent).toContain('Adicione tags'))
    ws.page('p1')!.tags = ['ideias']
    for (const other of ws.pages) if (other.id !== 'p1') other.tags = ['leitura'] // nobody else uses "ideias"
    await waitFor(() => expect(panel().getByTestId('no-related').textContent).toContain('Nenhuma outra página'))
  })

  it('"Fixar página" alterna e o texto muda', async () => {
    open()
    await click(panel().getByRole('button', { name: 'Fixar página' }))
    expect(ws.page('p0')!.pinned).toBe(true)
    await click(panel().getByRole('button', { name: 'Desafixar página' }))
    expect(ws.page('p0')!.pinned).toBe(false)
  })

  it('"Duplicar página" cria a cópia e abre', async () => {
    const onopen = vi.fn()
    render(Editor, { ws, id: 'p0', onback: vi.fn(), onopen })
    const before = ws.pages.length
    await click(panel().getByRole('button', { name: 'Duplicar página' }))
    expect(ws.pages).toHaveLength(before + 1)
    expect(onopen).toHaveBeenCalledWith(ws.pages[0].id)
    expect(ws.pages[0].title).toBe('Rotina de encerramento do trimestre (cópia)')
    expect(toast.message).toBe('Página duplicada')
  })

  it('duplicar avisa quando imagens ficam para trás', async () => {
    ws.page('p0')!.content!.push({ id: 'im', type: 'image', name: 'a.png', src: 'blob:a' })
    render(Editor, { ws, id: 'p0', onback: vi.fn(), onopen: vi.fn() })
    await click(panel().getByRole('button', { name: 'Duplicar página' }))
    expect(toast.message).toContain('imagens não foram copiadas')
  })

  it('sem permissão de exportar não há "Duplicar"; na lixeira não há ações', () => {
    open('s2')
    expect(panel().queryByRole('button', { name: 'Duplicar página' })).toBeNull()
    ws.trash('p1')
    open('p1')
    const bars = screen.getAllByRole('complementary', { name: 'Painel da página' })
    expect(within(bars.at(-1)!).queryByRole('button', { name: /Fixar|Duplicar/ })).toBeNull()
  })

  it('numa tela estreita o painel começa fechado e abre como gaveta, que se fecha sozinha ao escolher', async () => {
    viewport.set(390)
    Element.prototype.scrollIntoView = vi.fn()
    open()
    expect(screen.queryByRole('complementary', { name: 'Painel da página' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Abrir painel' }))
    expect(panel().getByRole('heading', { name: 'Detalhes' })).toBeTruthy()
    await click(panel().getByRole('button', { name: 'O que precisa acontecer antes do dia 31' }))
    expect(screen.queryByRole('complementary', { name: 'Painel da página' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Abrir painel' }))
    await click(screen.getByRole('button', { name: 'Fechar painel' }))
    expect(screen.queryByRole('complementary', { name: 'Painel da página' })).toBeNull()
  })

  it('o painel não aparece numa página do cofre trancada', () => {
    open('p4')
    expect(screen.queryByRole('button', { name: /Abrir (painel|propriedades)|Fechar (painel|propriedades)/ })).toBeNull()
    expect(screen.queryByRole('complementary')).toBeNull()
  })

  it('axe: painel aberto no desktop e a gaveta no celular', async () => {
    const { unmount } = open()
    expect(await violations()).toEqual([])
    unmount()
    viewport.set(390)
    open()
    await click(screen.getByRole('button', { name: 'Abrir painel' }))
    expect(await violations()).toEqual([])
  })
})

describe('Editor — página vazia', () => {
  it('oferece começar com um bloco; escolher cria o bloco e some a oferta', async () => {
    const fresh = ws.newPage()
    render(Editor, { ws, id: fresh.id, onback: vi.fn() })
    const group = within(screen.getByRole('group', { name: 'Começar com' }))
    expect(group.getAllByRole('button').map((b) => b.textContent)).toEqual(['Texto', 'Título', 'Checklist', 'Tabela', 'Código'])
    await click(group.getByRole('button', { name: 'Checklist' }))
    expect(kindsOf()).toEqual(['Checklist'])
    expect(screen.queryByRole('group', { name: 'Começar com' })).toBeNull()
  })

  it('uma página com conteúdo, ou só para leitura, não mostra a oferta', () => {
    open()
    expect(screen.queryByRole('group', { name: 'Começar com' })).toBeNull()
    const fresh = ws.newPage()
    ws.trash(fresh.id)
    render(Editor, { ws, id: fresh.id, onback: vi.fn() })
    expect(screen.queryByRole('group', { name: 'Começar com' })).toBeNull()
  })
})

describe('Editor — estilo Notion: ícone, capa, propriedades e caminho', () => {
  it('mostra a capa, o ícone e o caminho da página', () => {
    open()
    expect(screen.getByTestId('cover')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Trocar ícone da página' }).textContent).toContain('📋')
    const crumb = within(screen.getByRole('navigation', { name: 'Caminho' }))
    expect(crumb.getByText(/Rotina de encerramento do trimestre/).getAttribute('aria-current')).toBe('page')
    expect(screen.getByTestId('crumb-edited').textContent).toMatch(/editada há/)
  })

  it('o caminho diz onde a página mora: cofre, compartilhadas e lixeira', () => {
    const { unmount } = open('p4')
    ws.unlockVault('1234')
    unmount()
    open('p4')
    expect(screen.getByRole('navigation', { name: 'Caminho' }).textContent).toContain('Cofre')
    cleanup()
    open('s1')
    expect(screen.getByRole('navigation', { name: 'Caminho' }).textContent).toContain('Compartilhadas comigo')
  })

  it('o título no caminho acompanha o que se digita', async () => {
    open()
    await type(screen.getByLabelText('Título da página'), 'Novo nome')
    expect(within(screen.getByRole('navigation', { name: 'Caminho' })).getByText(/Novo nome/)).toBeTruthy()
  })

  it('trocar o ícone: abre a lista, escolhe, e remover tira', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
    const dialog = within(screen.getByRole('dialog', { name: 'Escolher ícone' }))
    await click(dialog.getByRole('tab', { name: 'Ideias' }))
    await click(dialog.getByRole('button', { name: 'Ícone 🔥' }))
    expect(ws.page('p0')!.icon).toBe('🔥')
    expect(screen.queryByRole('dialog', { name: 'Escolher ícone' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
    await click(screen.getByRole('button', { name: 'Remover ícone' }))
    expect(ws.page('p0')!.icon).toBe('')
    expect(screen.getByRole('button', { name: /Adicionar ícone/ })).toBeTruthy()
  })

  it('Esc fecha a lista de ícones sem sair do zen nem da página', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
    await keys(screen.getByRole('dialog', { name: 'Escolher ícone' }), 'Escape')
    expect(screen.queryByRole('dialog', { name: 'Escolher ícone' })).toBeNull()
  })

  it('capa: trocar, remover e adicionar de novo', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Trocar capa' }))
    await click(screen.getByRole('button', { name: 'Capa Oceano' }))
    expect(ws.page('p0')!.cover).toBe('oceano')
    await click(screen.getByRole('button', { name: 'Remover capa' }))
    expect(screen.queryByTestId('cover')).toBeNull()
    await click(screen.getByRole('button', { name: /Adicionar capa/ }))
    expect(ws.page('p0')!.cover).toBe('musgo')
    expect(screen.getByTestId('cover')).toBeTruthy()
  })

  it('quem só lê não vê botões de ícone nem de capa', () => {
    open('s2')
    expect(screen.queryByRole('button', { name: /Adicionar (ícone|capa)/ })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Trocar capa' })).toBeNull()
  })

  it('as propriedades mostram dono, datas e o progresso; página de outra pessoa mostra quem é o dono', () => {
    const { unmount } = open()
    const props = within(screen.getByTestId('meta'))
    expect(props.getByText('Dono').nextElementSibling!.textContent).toBe('Você')
    expect(props.getByText('Conteúdo').nextElementSibling!.textContent).toMatch(/7 blocos.*2 de 4 feitas/)
    unmount()
    open('s1')
    expect(within(screen.getByTestId('meta')).getByText('Dono').nextElementSibling!.textContent).toBe('Caio')
  })
})

describe('Editor — blocos novos', () => {
  it('o menu "/" oferece citação, destaque, toggle e divisor', async () => {
    open()
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    const names = screen.getAllByRole('menuitem').map((m) => m.textContent!.trim().replace(/^\S+\s+/, ''))
    for (const n of ['Citação', 'Destaque', 'Toggle', 'Divisor']) expect(names).toContain(n)
    await click(screen.getByRole('menuitem', { name: /Citação/ }))
    expect(kindsOf()[2]).toBe('Citação')
    expect(document.activeElement).toBe(screen.getByLabelText('Citação'))
  })

  it('divisor é só uma linha, sem campo para digitar', async () => {
    open()
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    await click(screen.getByRole('menuitem', { name: /Divisor/ }))
    expect(kindsOf()[2]).toBe('Divisor')
    expect(blockEls()[2].querySelector('hr')).toBeTruthy()
    expect(blockEls()[2].querySelector('textarea')).toBeNull()
  })

  it('toggle abre e fecha, e Enter no título vai para o conteúdo', async () => {
    open()
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    await click(screen.getByRole('menuitem', { name: /Toggle/ }))
    expect(screen.queryByLabelText('Conteúdo do toggle')).toBeNull()
    const { inst, dom } = await rich('Título do toggle')
    await put(inst, 'Detalhes')
    await keys(dom, 'Enter')
    const body = screen.getByLabelText('Conteúdo do toggle')
    expect(document.activeElement).toBe(body)
    await type(body, 'texto escondido')
    expect(ws.page('p0')!.content!.find((b) => b.type === 'toggle')).toMatchObject({ text: 'Detalhes', body: 'texto escondido' })
    await click(screen.getByRole('button', { name: 'Fechar toggle' }))
    expect(screen.queryByLabelText('Conteúdo do toggle')).toBeNull()
    expect(screen.getByRole('button', { name: 'Abrir toggle' }).getAttribute('aria-expanded')).toBe('false')
  })

  it('o menu do bloco duplica e transforma', async () => {
    open()
    const before = kindsOf().length
    await click(screen.getByRole('button', { name: 'Opções de Parágrafo 2' }))
    await click(screen.getByRole('menuitem', { name: 'Duplicar' }))
    expect(kindsOf().length).toBe(before + 1)
    expect(kindsOf().slice(1, 3)).toEqual(['Parágrafo', 'Parágrafo'])
    await click(screen.getByRole('button', { name: 'Opções de Parágrafo 2' }))
    expect(screen.queryByRole('menuitem', { name: 'Texto' })).toBeNull()
    await click(screen.getByRole('menuitem', { name: 'Destaque' }))
    expect(kindsOf().slice(1, 3)).toEqual(['Destaque', 'Parágrafo'])
  })

  it('só blocos de texto têm "Transformar em"; a imagem não duplica', async () => {
    open()
    await click(screen.getByRole('button', { name: /Opções de Bloco seguro/ }))
    expect(screen.queryByText('Transformar em')).toBeNull()
    await click(screen.getByRole('button', { name: /Opções de Bloco de código/ }))
    expect(screen.queryByRole('menuitem', { name: 'Citação' })).toBeNull()
  })

  it('o bloco seguro não ganha a barra de formatação', async () => {
    ws.unlockVault('1234')
    open()
    expect(document.querySelector('[data-block-id] textarea[aria-label="Texto do bloco seguro"]')).toBeNull()
  })
})

describe('Editor — barra de formatação', () => {
  /** Selects words of the open block the way a person does, so the bar follows. */
  const pick = (inst: RichInstance, from: number, to: number) => {
    inst.setSelection(from, to)
    document.dispatchEvent(new Event('selectionchange'))
  }
  const bar = () => screen.queryByRole('toolbar', { name: 'Formatar texto' })

  it('aparece ao selecionar texto e some ao soltar a seleção', async () => {
    open()
    expect(bar()).toBeNull()
    const { inst } = await rich()
    pick(inst, 0, 5)
    await waitFor(() => expect(bar()).toBeTruthy())
    pick(inst, 3, 3)
    await waitFor(() => expect(bar()).toBeNull())
  })

  it('negrito, itálico e código gravam os marcadores no texto da página', async () => {
    open()
    const { inst } = await rich()
    const original = plain(inst)
    pick(inst, 2, 12)
    await waitFor(() => screen.getByRole('toolbar', { name: 'Formatar texto' }))
    await click(screen.getByRole('button', { name: 'Negrito' }))
    expect(ws.page('p0')!.content![1]).toMatchObject({ text: `${original.slice(0, 2)}**fechamento**${original.slice(12)}` })
    expect(inst.runs().find((r) => r.text === 'fechamento')!.marks.bold).toBe(true)
    // code holds no other marks: it replaces the bold
    await click(screen.getByRole('button', { name: 'Código' }))
    expect(inst.runs().find((r) => r.text === 'fechamento')!.marks).toEqual({ code: true })
    expect((ws.page('p0')!.content![1] as { text: string }).text).toContain('`fechamento`')
  })

  it('Ctrl+B e Ctrl+I funcionam sem a barra', async () => {
    open()
    const { inst, dom } = await rich()
    const original = plain(inst)
    inst.setSelection(2, 12)
    await keys(dom, 'b', { ctrlKey: true })
    expect((ws.page('p0')!.content![1] as { text: string }).text).toBe(`${original.slice(0, 2)}**fechamento**${original.slice(12)}`)
    await keys(dom, 'i', { ctrlKey: true })
    expect((ws.page('p0')!.content![1] as { text: string }).text).toContain('***fechamento***')
  })

  it('numa página que não se pode editar, a barra não aparece', async () => {
    ws.trash('p0')
    open()
    drawn().focus()
    await tick()
    noEditor()
    expect(bar()).toBeNull()
  })

  it('o bloco seguro não ganha a barra de formatação', async () => {
    ws.unlockVault('1234')
    open()
    expect(document.querySelector('[data-block-id] textarea[aria-label="Texto do bloco seguro"]')).toBeNull()
  })

  it('a barra traz negrito, itálico, sublinhado, riscado, marca-texto, código e link', async () => {
    open()
    const { inst } = await rich()
    pick(inst, 2, 12)
    const buttons = within(await screen.findByRole('toolbar', { name: 'Formatar texto' }))
    expect(buttons.getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual(['Negrito', 'Itálico', 'Sublinhado', 'Riscado', 'Marca-texto', 'Código', 'Link', 'Tirar link'])
    await click(buttons.getByRole('button', { name: 'Sublinhado' }))
    expect((ws.page('p0')!.content![1] as { text: string }).text).toContain('__fechamento__')
  })

  it('Ctrl+Shift+outra letra não faz nada, e os atalhos ligam e desligam', async () => {
    open()
    const { inst, dom } = await rich()
    const original = (ws.page('p0')!.content![1] as { text: string }).text
    inst.setSelection(2, 12)
    await keys(dom, 'i', { ctrlKey: true })
    expect((ws.page('p0')!.content![1] as { text: string }).text).toContain('*fechamento*')
    await keys(dom, 'i', { ctrlKey: true })
    expect((ws.page('p0')!.content![1] as { text: string }).text).toBe(original)
    await keys(dom, 'q', { ctrlKey: true, shiftKey: true })
    expect((ws.page('p0')!.content![1] as { text: string }).text).toBe(original)
  })
})

describe('Editor — modo zen', () => {
  it('esconde o cabeçalho, as propriedades, a capa, o painel e as alças; mostra palavras e como sair', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    expect(screen.queryByRole('banner')).toBeNull()
    expect(screen.queryByTestId('meta')).toBeNull()
    expect(screen.queryByTestId('cover')).toBeNull()
    expect(screen.queryByRole('complementary')).toBeNull()
    expect(screen.queryByRole('button', { name: /Opções de/ })).toBeNull()
    expect(Number(screen.getByTestId('zen-words').textContent!.split(' ')[0])).toBeGreaterThan(10)
    expect(screen.getByLabelText('Título da página')).toBeTruthy()
  })

  it('Esc e o botão saem do zen e tudo volta', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    await keys(window, 'Escape')
    expect(screen.getByRole('banner')).toBeTruthy()
    expect(screen.getByTestId('meta')).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    await click(screen.getByRole('button', { name: /Sair do zen/ }))
    expect(screen.getByRole('banner')).toBeTruthy()
  })

  it('dá para continuar escrevendo e o contador acompanha', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    const words = () => Number(screen.getByTestId('zen-words').textContent!.split(' ')[0])
    const before = words()
    const { inst } = await rich()
    await put(inst, plain(inst) + ' mais cinco palavras aqui agora')
    expect(words()).toBe(before + 5)
  })

  it('Esc num menu aberto fecha só o menu, não o zen', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    const draft = screen.getByLabelText('Nova linha')
    await type(draft, '/')
    await keys(screen.getByRole('menu', { name: 'Inserir bloco' }), 'Escape')
    expect(screen.queryByRole('menu', { name: 'Inserir bloco' })).toBeNull()
    expect(screen.getByTestId('zen-words')).toBeTruthy()
  })

  it('o zen não aparece em página trancada nem em página inexistente', () => {
    open('nao-existe')
    expect(screen.queryByRole('button', { name: 'Modo zen' })).toBeNull()
    cleanup()
    open('p4')
    expect(screen.queryByRole('button', { name: 'Modo zen' })).toBeNull()
  })

  it('axe: página com capa, ícone, propriedades e o modo zen', async () => {
    open()
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    expect(await violations()).toEqual([])
  })
})

describe('Editor — texto formatado (desenhado fora da edição)', () => {
  const marked = (text: string) => {
    ws.contentOf('p0')
    const p = ws.page('p0')!.content!.find((b) => b.type === 'paragraph') as { text: string }
    p.text = text
  }

  it('fora da edição o bloco aparece formatado; em foco vira o editor, com as mesmas marcas', async () => {
    marked('um **forte** e *suave* com `código`')
    open()
    const view = drawn()
    expect(view.tagName).toBe('DIV')
    expect(view.getAttribute('aria-readonly')).toBe('true')
    expect(view.querySelector('strong')!.textContent).toBe('forte')
    expect(view.querySelector('em')!.textContent).toBe('suave')
    expect(view.querySelector('code')!.textContent).toBe('código')
    expect(view.textContent).not.toContain('**')
    const { inst, dom } = await rich()
    expect(dom.querySelector('strong')!.textContent).toBe('forte')
    expect(dom.querySelector('em')!.textContent).toBe('suave')
    expect(inst.selection()).toEqual({ from: plain(inst).length, to: plain(inst).length })
    // what is stored keeps its symbols
    expect((ws.page('p0')!.content![1] as { text: string }).text).toBe('um **forte** e *suave* com `código`')
  })

  it('ao sair do editor o bloco volta a aparecer formatado', async () => {
    marked('um **forte**')
    open()
    const { dom } = await rich()
    await fireEvent.blur(dom)
    await waitFor(() => expect(drawn().tagName).toBe('DIV'))
    noEditor()
    expect(drawn().querySelector('strong')!.textContent).toBe('forte')
  })

  it('digitar símbolos com o editor aberto não o troca no meio da digitação', async () => {
    open()
    const { inst } = await rich()
    await put(inst, 'olá **mundo**')
    expect(document.querySelector('[data-rich] [aria-label="Parágrafo"]')).not.toBeNull()
    expect(inst.runs().find((r) => r.text === 'mundo')!.marks.bold).toBe(true)
  })

  it('texto sem marcas, ou com marcas soltas, é só texto até receber o foco', () => {
    marked('snake_case_name e 2 * 3 * 4 e [colchetes] e a_b')
    open()
    expect(drawn().tagName).toBe('DIV')
    expect(drawn().textContent).toBe('snake_case_name e 2 * 3 * 4 e [colchetes] e a_b')
    expect(drawn().querySelector('em, strong, u, s')).toBeNull()
    expect(document.querySelectorAll('textarea[aria-label="Parágrafo"]').length).toBe(0)
  })

  it('as setas entram num bloco formatado vindo do vizinho, com o cursor no começo', async () => {
    marked('um **forte**')
    open()
    const { inst, dom } = await rich('Título de seção')
    inst.setSelection(plain(inst).length, plain(inst).length)
    await keys(dom, 'ArrowDown')
    await waitFor(() => expect(document.querySelector('[data-rich] [aria-label="Parágrafo"]')).not.toBeNull())
    expect(current('Parágrafo').inst.selection()).toEqual({ from: 0, to: 0 })
  })

  it('axe: bloco formatado desenhado e em edição', async () => {
    marked('um **forte** com [link](https://a.com)')
    open()
    expect(await violations()).toEqual([])
    await rich()
    expect(await violations()).toEqual([])
  })
})

describe('Editor — capas e ícones ampliados', () => {
  beforeEach(() => {
    prefs.setIconAlign('left')
    prefs.recentIcons = []
  })
  const coverMenu = async () => {
    await click(screen.getByRole('button', { name: 'Trocar capa' }))
    return within(screen.getByRole('dialog', { name: 'Escolher capa' }))
  }

  it('o seletor de capa tem combinações, duas cores, degradê, lisa e clássicas', async () => {
    open()
    const menu = await coverMenu()
    for (const group of ['Combinações de cores', 'Duas cores', 'Uma cor em degradê', 'Cor lisa', 'Capas clássicas', 'Posição do ícone']) expect(menu.getByRole('group', { name: group })).toBeTruthy()
    await click(menu.getByRole('button', { name: 'Capa Arco-íris' }))
    expect(ws.page('p0')!.cover).toBe('mix:arco-iris')
    expect(screen.getByTestId('cover').getAttribute('style')).toContain('linear-gradient')
  })

  it('degradê de uma cor e cor lisa', async () => {
    open()
    let menu = await coverMenu()
    await click(menu.getByRole('button', { name: 'Degradê Rosa' }))
    expect(ws.page('p0')!.cover).toBe('mono:rosa')
    await click(menu.getByRole('button', { name: 'Lisa Ouro' }))
    expect(ws.page('p0')!.cover).toBe('solid:ouro')
    expect(menu.getByRole('button', { name: 'Lisa Ouro' }).getAttribute('aria-pressed')).toBe('true')
  })

  it('duas cores: início, fim e direção, e cada escolha vale na hora', async () => {
    open()
    const menu = await coverMenu()
    await click(menu.getByRole('button', { name: 'Início Rosa' }))
    expect(ws.page('p0')!.cover).toBe('duo:rosa:ferrugem:dr')
    await click(menu.getByRole('button', { name: 'Fim Azul' }))
    expect(ws.page('p0')!.cover).toBe('duo:rosa:azul:dr')
    await click(menu.getByRole('button', { name: 'Para baixo' }))
    expect(ws.page('p0')!.cover).toBe('duo:rosa:azul:d')
    expect(menu.getByRole('button', { name: 'Início Rosa' }).getAttribute('aria-pressed')).toBe('true')
    expect(menu.getByRole('button', { name: 'Para baixo' }).getAttribute('aria-pressed')).toBe('true')
    await click(menu.getByRole('button', { name: 'Início Ouro' }))
    expect(ws.page('p0')!.cover).toBe('duo:ouro:azul:d')
  })

  it('o seletor fecha com Esc e ao clicar fora, e a escolha continua', async () => {
    open()
    const menu = await coverMenu()
    await keys(screen.getByRole('dialog', { name: 'Escolher capa' }), 'Escape')
    expect(screen.queryByRole('dialog', { name: 'Escolher capa' })).toBeNull()
    await coverMenu()
    await fireEvent.mouseDown(document.body)
    expect(screen.queryByRole('dialog', { name: 'Escolher capa' })).toBeNull()
    void menu
  })

  it('uma capa ou ícone corrompidos (vindos de fora) não quebram a página', () => {
    ws.page('p0')!.cover = 'lixo:xxx'
    ws.page('p0')!.icon = '<b>'
    open()
    expect(screen.queryByTestId('cover')).toBeNull()
    expect(screen.getByLabelText('Título da página')).toBeTruthy()
  })

  it('o ícone cruza a borda da capa; "No centro" o centraliza', async () => {
    open()
    const row = () => screen.getByTestId('icon-row')
    expect(row().className).toContain('-mt-20')
    expect(row().className).not.toContain('justify-center')
    const menu = await coverMenu()
    await click(menu.getByRole('button', { name: 'No centro' }))
    expect(prefs.iconAlign).toBe('center')
    expect(row().className).toContain('justify-center')
    await click(menu.getByRole('button', { name: 'Na coluna' }))
    expect(row().className).not.toContain('justify-center')
  })

  it('sem capa o ícone fica na coluna, sem cruzar nada', async () => {
    ws.page('p0')!.cover = ''
    open()
    expect(screen.getByTestId('icon-row').className).not.toContain('-mt-20')
  })

  it('o seletor de ícones tem grupos, e trocar de grupo troca a lista', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
    const dialog = within(screen.getByRole('dialog', { name: 'Escolher ícone' }))
    expect(dialog.getAllByRole('tab').length).toBeGreaterThanOrEqual(8)
    const count = () => dialog.getAllByRole('button', { name: /^Ícone / }).length
    const first = count()
    expect(first).toBeGreaterThan(30)
    await click(dialog.getByRole('tab', { name: 'Comida' }))
    expect(dialog.getByRole('tab', { name: 'Comida' }).getAttribute('aria-selected')).toBe('true')
    expect(dialog.getByRole('button', { name: 'Ícone 🍕' })).toBeTruthy()
    expect(dialog.queryByRole('button', { name: 'Ícone 📋' })).toBeNull()
  })

  it('cole qualquer emoji: pega o primeiro de um texto, e recusa o que não tem emoji', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
    const input = screen.getByLabelText('Colar qualquer emoji') as HTMLInputElement
    await type(input, 'abc')
    await fireEvent.submit(input.closest('form')!)
    expect(ws.page('p0')!.icon).toBe('📋')
    expect(input.value).toBe('')
    await type(input, 'olá 🦄 mundo')
    await fireEvent.submit(input.closest('form')!)
    expect(ws.page('p0')!.icon).toBe('🦄')
    expect(screen.queryByRole('dialog', { name: 'Escolher ícone' })).toBeNull()
  })

  it('os ícones usados aparecem como recentes, sem repetir, no máximo doze', async () => {
    open()
    for (const e of ['🔥', '🧠', '🔥', '🦊', '🍕']) {
      await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
      await type(screen.getByLabelText('Colar qualquer emoji'), e)
      await fireEvent.submit(screen.getByLabelText('Colar qualquer emoji').closest('form')!)
    }
    expect(prefs.recentIcons).toEqual(['🍕', '🦊', '🔥', '🧠'])
    await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
    const recents = within(screen.getByRole('group', { name: 'Usados há pouco' }))
    expect(recents.getAllByRole('button').map((b) => b.textContent)).toEqual(['🍕', '🦊', '🔥', '🧠'])
    await click(recents.getByRole('button', { name: 'Recente 🧠' }))
    expect(ws.page('p0')!.icon).toBe('🧠')
    for (let i = 0; i < 20; i++) prefs.rememberIcon(String.fromCodePoint(0x1f600 + i))
    expect(prefs.recentIcons).toHaveLength(12)
  })

  it('animações: blocos entram em cascata, menus aparecem com "pop", e tudo respeita reduzir movimento', async () => {
    open()
    const rows = blockEls()
    expect(rows[0].className).toContain('animate-rise')
    expect(rows[0].style.animationDelay).toBe('0ms')
    expect(rows[3].style.animationDelay).toBe('84ms')
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    expect(screen.getByRole('menu', { name: 'Inserir bloco' }).className).toContain('animate-pop')
    const css = readFileSync('src/app.css', 'utf8')
    expect(css).toMatch(/prefers-reduced-motion: reduce[\s\S]*animation-duration: 0\.01ms !important/)
    for (const k of ['pop-in', 'rise-in', 'fade-in', 'slide-in-right', 'icon-pop']) expect(css).toContain(`@keyframes ${k}`)
  })

  it('a cascata tem teto: o décimo-quinto bloco não espera mais que o décimo', async () => {
    open()
    for (let i = 0; i < 14; i++) ws.page('p0')!.content!.push({ id: `x${i}`, type: 'divider' })
    await tick()
    const rows = blockEls()
    expect(rows.length).toBeGreaterThan(14)
    expect(rows[14].style.animationDelay).toBe('280ms')
  })

  it('o painel e o zen também entram com movimento', async () => {
    open()
    expect(document.querySelector('.animate-slide-left')).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    expect(screen.getByTestId('zen-words').parentElement!.className).toContain('animate-fade')
  })

  it('axe: seletores de capa e de ícone abertos', async () => {
    open()
    await coverMenu()
    expect(await violations()).toEqual([])
    await fireEvent.mouseDown(document.body)
    await click(screen.getByRole('button', { name: 'Trocar ícone da página' }))
    expect(await violations()).toEqual([])
  })
})

describe('Editor — propriedades à esquerda, painel à direita, ambos com seta', () => {
  beforeEach(() => {
    stubLocalStorage()
    prefs.folded = []
  })
  const left = () => within(screen.getByTestId('dock-left'))
  const right = () => within(screen.getByTestId('dock'))

  it('no desktop as propriedades vêm abertas à esquerda e o painel à direita, fora do fluxo da página', () => {
    open()
    expect(screen.getByTestId('dock-left').className).toContain('left-0')
    expect(screen.getByTestId('dock').className).toContain('right-0')
    expect(screen.getByTestId('dock-left').className).toContain('absolute')
    expect(left().getByRole('complementary', { name: 'Propriedades da página' })).toBeTruthy()
    expect(left().getByTestId('meta')).toBeTruthy()
    expect(right().getByRole('complementary', { name: 'Painel da página' })).toBeTruthy()
    // properties live in their panel, not in the page
    expect(document.querySelector('article [data-testid="meta"]')).toBeNull()
  })

  it('cada seta fecha o seu lado e a página não muda de lugar nem de classes', async () => {
    open()
    const article = document.querySelector('article')!
    const before = article.className
    await click(left().getByRole('button', { name: 'Fechar propriedades' }))
    expect(left().queryByTestId('meta')).toBeNull()
    expect(article.className).toBe(before)
    await click(right().getByRole('button', { name: 'Fechar painel' }))
    expect(right().queryByRole('complementary')).toBeNull()
    expect(article.className).toBe(before)
    await click(left().getByRole('button', { name: 'Abrir propriedades' }))
    await click(right().getByRole('button', { name: 'Abrir painel' }))
    expect(left().getByTestId('meta')).toBeTruthy()
    expect(right().getByRole('complementary')).toBeTruthy()
    expect(article.className).toBe(before)
  })

  it('a seta aponta para onde o painel vai: para a borda ao fechar, para a página ao abrir', async () => {
    open()
    const path = (b: HTMLElement) => b.querySelector('path')!.getAttribute('d')
    const L = 'm15 6-6 6 6 6'
    const R = 'm9 6 6 6-6 6'
    expect(path(left().getByRole('button', { name: 'Fechar propriedades' }))).toBe(L)
    expect(path(right().getByRole('button', { name: 'Fechar painel' }))).toBe(R)
    await click(left().getByRole('button', { name: 'Fechar propriedades' }))
    await click(right().getByRole('button', { name: 'Fechar painel' }))
    expect(path(left().getByRole('button', { name: 'Abrir propriedades' }))).toBe(R)
    expect(path(right().getByRole('button', { name: 'Abrir painel' }))).toBe(L)
  })

  it('a seta é grande e a seta fica centralizada no botão', () => {
    open()
    const b = right().getByRole('button', { name: 'Fechar painel' })
    expect(b.className).toContain('size-11')
    expect(b.className).toContain('place-items-center')
    expect(b.querySelector('svg')!.getAttribute('width')).toBe('22')
  })

  it('as escolhas ficam lembradas, uma para cada lado', async () => {
    const storage = stubLocalStorage()
    const { unmount } = open()
    await click(left().getByRole('button', { name: 'Fechar propriedades' }))
    expect(storage.get('pindrel:editor-props')).toBe('0')
    expect(storage.get('pindrel:editor-panel')).toBeUndefined()
    unmount()
    open()
    expect(screen.getByTestId('dock-left').querySelector('[data-testid="meta"]')).toBeNull()
    expect(right().getByRole('complementary')).toBeTruthy()
  })

  it('cada seção do painel dobra e desdobra, e dobrar uma não mexe nas outras', async () => {
    open()
    const details = right().getByRole('button', { name: /Detalhes/ })
    expect(details.getAttribute('aria-expanded')).toBe('true')
    await click(details)
    expect(details.getAttribute('aria-expanded')).toBe('false')
    expect(right().queryByTestId('stat-words')).toBeNull()
    expect(right().getByRole('button', { name: /Relacionadas/ }).getAttribute('aria-expanded')).toBe('true')
    expect(prefs.folded).toEqual(['details'])
    await click(details)
    expect(right().getByTestId('stat-words')).toBeTruthy()
  })

  it('em tela estreita (a partir de 360 px) nada vem aberto, e cada seta fica na borda da tela', async () => {
    viewport.set(390)
    open()
    expect(screen.queryByTestId('dock')).toBeNull()
    expect(screen.queryByRole('complementary')).toBeNull()
    expect(screen.queryByRole('button', { name: 'Painel da página' })).toBeNull()
    const lefty = screen.getByRole('button', { name: 'Abrir propriedades' })
    const righty = screen.getByRole('button', { name: 'Abrir painel' })
    expect(lefty.className).toContain('left-0')
    expect(righty.className).toContain('right-0')
    expect(lefty.className).toContain('fixed')
  })

  it('no celular a seta abre uma gaveta de cada lado, que fecha pela seta, pelo fundo e ao compartilhar', async () => {
    viewport.set(390)
    open()
    await click(screen.getByRole('button', { name: 'Abrir propriedades' }))
    expect(screen.getByRole('complementary', { name: 'Propriedades da página' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Abrir painel' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Fechar propriedades' }))
    expect(screen.queryByRole('complementary')).toBeNull()
    await click(screen.getByRole('button', { name: 'Abrir painel' }))
    expect(screen.getByRole('complementary', { name: 'Painel da página' })).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Fechar painel (fundo)' }))
    expect(screen.queryByRole('complementary')).toBeNull()
    await click(screen.getByRole('button', { name: 'Abrir propriedades' }))
    await click(screen.getByRole('button', { name: /Retirar acesso/ }))
    expect(screen.getByRole('dialog', { name: 'Compartilhar' })).toBeTruthy()
    expect(screen.queryByRole('complementary')).toBeNull()
  })

  it('sem espaço para a seta (menos de 360 px) o cabeçalho leva os botões', async () => {
    viewport.set(340)
    open()
    expect(screen.queryByRole('button', { name: 'Abrir painel' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Abrir propriedades' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    await click(screen.getByRole('menuitem', { name: 'Propriedades' }))
    expect(screen.getByRole('complementary', { name: 'Propriedades da página' })).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Fechar propriedades' }))
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    await click(screen.getByRole('menuitem', { name: 'Painel' }))
    expect(screen.getByRole('complementary', { name: 'Painel da página' })).toBeTruthy()
  })

  it('em tela larga o cabeçalho não leva o botão do painel', () => {
    open()
    expect(screen.queryByRole('button', { name: 'Painel da página' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Propriedades da página' })).toBeNull()
  })

  it('no zen e numa página trancada nenhuma seta aparece', async () => {
    open()
    await click(screen.getByRole('button', { name: 'Modo zen' }))
    expect(screen.queryByRole('button', { name: /painel|propriedades/i })).toBeNull()
    cleanup()
    viewport.set(390)
    open('p4')
    expect(screen.queryByRole('button', { name: /Abrir/ })).toBeNull()
  })

  it('axe: tudo aberto, tudo fechado, gavetas', async () => {
    open()
    expect(await violations()).toEqual([])
    await click(left().getByRole('button', { name: 'Fechar propriedades' }))
    await click(right().getByRole('button', { name: 'Fechar painel' }))
    expect(await violations()).toEqual([])
    cleanup()
    viewport.set(390)
    open()
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: 'Abrir propriedades' }))
    expect(await violations()).toEqual([])
  })
})

describe('Editor — só o que está perto da tela vira campo de texto', () => {
  type Cb = (entries: { target: Element; isIntersecting: boolean }[]) => void
  let cb: Cb
  const observed = new Set<Element>()
  const report = (el: Element, isIntersecting: boolean) => cb([{ target: el, isIntersecting }])
  const stubObserver = () => {
    ;(globalThis as Record<string, unknown>).IntersectionObserver = (
      class {
        constructor(c: Cb) {
          cb = c
        }
        observe(el: Element) {
          observed.add(el)
        }
        unobserve(el: Element) {
          observed.delete(el)
        }
        disconnect() {}
      }
    )
    resetNearView()
  }
  beforeEach(() => {
    observed.clear()
    stubObserver()
  })
  afterEach(() => {
    delete (globalThis as Record<string, unknown>).IntersectionObserver
    resetNearView()
  })
  const wrappers = () => [...observed]
  const para = () => screen.getByLabelText('Parágrafo')


  it('ao sair, volta a ser texto sem perder uma letra', async () => {
    open()
    const { inst, dom } = await rich()
    await put(inst, 'texto novo, escrito agora')
    await fireEvent.blur(dom)
    await waitFor(() => expect(drawn().tagName).toBe('DIV'))
    expect(drawn().textContent).toBe('texto novo, escrito agora')
    expect(ws.page('p0')!.content![1]).toMatchObject({ text: 'texto novo, escrito agora' })
  })

  it('o bloco em edição continua aberto mesmo que saia de perto da tela', async () => {
    open()
    const { dom } = await rich()
    dom.focus()
    const el = wrappers().find((w) => w.querySelector('[aria-label="Parágrafo"]'))!
    report(el, true)
    report(el, false)
    await tick()
    expect(document.querySelector('[data-rich] [aria-label="Parágrafo"]')).not.toBeNull()
  })

  it('clicar ou dar Tab num bloco o abre no editor, com o cursor no fim', async () => {
    open()
    const { inst } = await rich()
    expect(plain(inst)).toContain('O fechamento tem três frentes')
    expect(inst.selection()).toEqual({ from: plain(inst).length, to: plain(inst).length })
  })

  it('as setas entram num bloco distante vindo do vizinho, com o cursor no começo', async () => {
    open()
    const heading = screen.getByLabelText('Título de seção')
    report(wrappers().find((w) => w.contains(heading))!, true)
    await tick()
    const { inst, dom } = await rich('Título de seção')
    inst.setSelection(plain(inst).length, plain(inst).length)
    await keys(dom, 'ArrowDown')
    await waitFor(() => expect(document.querySelector('[data-rich] [aria-label="Parágrafo"]')).not.toBeNull())
    expect(current('Parágrafo').inst.selection()).toEqual({ from: 0, to: 0 })
  })

  it('um bloco vazio distante mantém a altura de uma linha', () => {
    ws.contentOf('p0')
    ;(ws.page('p0')!.content!.find((b) => b.type === 'paragraph') as { text: string }).text = ''
    open()
    expect(para().tagName).toBe('DIV')
    expect(para().textContent).toBe('​')
  })

  it('o bloco seguro nunca vira texto, perto ou longe', () => {
    ws.unlockVault('1234')
    open()
    const secure = document.querySelector('[data-block-id] textarea[aria-label="Texto do bloco seguro"], [data-block-id] [aria-label="Texto do bloco seguro"]')
    expect(secure === null || secure.tagName === 'TEXTAREA').toBe(true)
  })

  it('o texto de um bloco distante continua sendo texto de verdade: nada de HTML, e a marcação aparece', () => {
    ws.contentOf('p0')
    ;(ws.page('p0')!.content!.find((b) => b.type === 'paragraph') as { text: string }).text = '<img src=x onerror=alert(1)> e **forte**'
    open()
    expect(para().querySelector('img')).toBeNull()
    expect(para().textContent).toContain('<img src=x onerror=alert(1)> e forte')
    expect(para().querySelector('strong')!.textContent).toBe('forte')
  })

  it('sair da página solta os observadores', () => {
    const { unmount } = open()
    expect(observed.size).toBeGreaterThan(0)
    unmount()
    expect(observed.size).toBe(0)
  })

  it('axe: blocos distantes (texto) e blocos perto (campos)', async () => {
    open()
    expect(await violations()).toEqual([])
    for (const el of wrappers()) report(el, true)
    await tick()
    expect(await violations()).toEqual([])
  })
})

describe('Editor — painéis que crescem com a tela, setas no meio, sublinhado', () => {
  beforeEach(() => {
    stubLocalStorage()
    prefs.folded = []
  })
  const setWidth = async (w: number) => {
    ;(window as unknown as { innerWidth: number }).innerWidth = w
    window.dispatchEvent(new Event('resize'))
    await tick()
  }
  afterEach(() => setWidth(1024))

  it('a seta fica no meio do painel, numa faixa à parte que não toca no texto', () => {
    open()
    const left = within(screen.getByTestId('dock-left'))
    const arrow = left.getByRole('button', { name: 'Fechar propriedades' })
    const rail = arrow.parentElement!
    expect(rail.className).toContain('items-center')
    expect(rail.className).toContain('justify-center')
    expect(rail.className).toContain('w-12')
    expect(rail.contains(left.getByTestId('meta'))).toBe(false)
    expect(left.getByRole('complementary').contains(arrow)).toBe(false)
    const right = within(screen.getByTestId('dock'))
    expect(right.getByRole('button', { name: 'Fechar painel' }).parentElement!.className).toContain('items-center')
  })

  it('a seta fica no mesmo lugar com o painel aberto e fechado', async () => {
    open()
    const parent = () => within(screen.getByTestId('dock-left')).getByRole('button', { name: /propriedades/ }).parentElement!
    const before = parent().className
    await click(within(screen.getByTestId('dock-left')).getByRole('button', { name: 'Fechar propriedades' }))
    expect(parent().className).toBe(before)
    expect(within(screen.getByTestId('dock-left')).queryByRole('complementary')).toBeNull()
  })

  it('o painel não tem rolagem para os lados', () => {
    open()
    const area = screen.getByTestId('dock').querySelector('.overflow-y-auto')!
    expect(area.className).toContain('overflow-x-hidden')
    expect(screen.getByTestId('dock-left').querySelector('.overflow-y-auto')!.className).toContain('overflow-x-hidden')
  })

  it('em telas maiores os painéis crescem; em 1340 ficam do tamanho base', async () => {
    await setWidth(1340)
    const { unmount } = open()
    expect(screen.getByTestId('dock').style.zoom).toBe('1')
    unmount()
    await setWidth(1864)
    open()
    const z = Number(screen.getByTestId('dock').style.zoom)
    expect(z).toBeGreaterThan(1.4)
    expect(Number(screen.getByTestId('dock-left').style.zoom)).toBe(z)
  })

  it('em tela gigante o crescimento tem teto', async () => {
    await setWidth(5000)
    open()
    expect(screen.getByTestId('dock').style.zoom).toBe('1.7')
  })





  it('o sublinhado não aparece em campo de bloco seguro', () => {
    ws.unlockVault('1234')
    open()
    expect(document.querySelector('[aria-label="Texto do bloco seguro"][data-fmt]')).toBeNull()
  })

  it('nenhum menu ganhou sublinhado de passar o mouse (isso era outra coisa)', () => {
    const css = readFileSync('src/app.css', 'utf8')
    expect(css).not.toContain("[role='menuitem'], [role='tab'], .opt")
  })
})

describe('Editor — menu de blocos com rolagem e categorias, cabeçalho compacto, capa no celular', () => {
  const openMenu = async () => {
    await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
    return screen.getByRole('menu', { name: 'Inserir bloco' })
  }

  it('o menu de inserir tem categorias, cada uma com seus blocos', async () => {
    open()
    const menu = within(await openMenu())
    const groups = menu.getAllByRole('group').map((g) => g.getAttribute('aria-label'))
    expect(groups).toEqual(['Texto', 'Listas e toggles', 'Mídia e links', 'Dados e código', 'Estrutura e sigilo'])
    const inside = (g: string) => within(menu.getByRole('group', { name: g })).getAllByRole('menuitem').map((m) => m.textContent!.trim().replace(/^\S+\s+/, ''))
    expect(inside('Texto')).toEqual(['Texto', 'Título 1', 'Título 2', 'Título 3', 'Citação', 'Destaque'])
    expect(inside('Listas e toggles')).toEqual(['Lista com marcadores', 'Lista numerada', 'Checklist', 'Toggle', 'Título 1 com toggle', 'Título 2 com toggle', 'Título 3 com toggle'])
    expect(inside('Mídia e links')).toEqual(['Imagem', 'Vídeo', 'Áudio', 'Arquivo', 'PDF', 'Link', 'Link para página'])
    expect(inside('Dados e código')).toEqual(['Tabela', 'Código'])
    expect(inside('Estrutura e sigilo')).toEqual(['Sumário', 'Divisor', 'Spoiler', 'Bloco seguro'])
  })

  it('rola dentro de si, cabe em telas pequenas, e fica sobre o texto, com fundo', async () => {
    viewport.set(320)
    open()
    const menu = await openMenu()
    expect(menu.className).toContain('overflow-y-auto')
    expect(menu.className).toContain('max-h-[min(24rem,55dvh)]')
    expect(menu.className).toContain('bg-surface')
    expect(menu.className).toContain('w-[min(14rem,calc(100vw-2rem))]')
    expect(menu.className).toContain('z-40')
    expect(menu.className).toContain('overscroll-contain')
  })

  it('a linha do menu aberto sobe acima das vizinhas, para ele não ficar por baixo do texto', async () => {
    open()
    const row = () => blockEls()[1]
    expect(row().className).not.toContain('z-30')
    await openMenu()
    expect(row().className).toContain('z-30')
    await keys(screen.getByRole('menu', { name: 'Inserir bloco' }), 'Escape')
    expect(row().className).not.toContain('z-30')
  })

  it('as setas percorrem as categorias em ordem e Esc fecha', async () => {
    open()
    await openMenu()
    const names = []
    for (let i = 0; i < 6; i++) {
      names.push(document.activeElement!.textContent!.trim().replace(/^\S+\s+/, ''))
      await keys(document.activeElement!, 'ArrowDown')
    }
    expect(names).toEqual(['Texto', 'Título 1', 'Título 2', 'Título 3', 'Citação', 'Destaque'])
    expect(document.activeElement!.textContent).toContain('Lista com marcadores')
  })

  it('as animações terminam no estado natural, sem manter uma camada que esconda o menu', () => {
    const css = readFileSync('src/app.css', 'utf8')
    for (const name of ['pop-in', 'rise-in', 'fade-in', 'slide-in-right', 'slide-in-left', 'icon-pop']) {
      expect(css).toMatch(new RegExp(`animation: ${name} [^;]*backwards;`))
    }
    expect(css).not.toMatch(/animation: [a-z-]+ [^;]*\b(both|forwards);/)
  })

  it('com menos de 480 px o cabeçalho junta zen e excluir em "Mais ações"; a partir daí tudo aparece', async () => {
    viewport.set(479)
    const { unmount } = open()
    expect(screen.getByRole('button', { name: 'Mais ações' })).toBeTruthy()
    unmount()
    viewport.set(480)
    open()
    expect(screen.queryByRole('button', { name: 'Mais ações' })).toBeNull()
    expect(screen.getByRole('button', { name: 'Modo zen' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Excluir página' })).toBeTruthy()
  })

  it('"Mais ações" abre o zen e a exclusão, e fecha com Esc e ao clicar fora', async () => {
    viewport.set(330)
    open()
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    await keys(window, 'Escape')
    expect(screen.queryByRole('menu', { name: 'Mais ações' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    await fireEvent.mouseDown(document.body)
    expect(screen.queryByRole('menu', { name: 'Mais ações' })).toBeNull()
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    await click(screen.getByRole('menuitem', { name: 'Modo zen' }))
    expect(screen.getByTestId('zen-words')).toBeTruthy()
    expect(screen.queryByRole('banner')).toBeNull()
  })

  it('"Excluir página" pelo menu pede confirmação, e numa página sem permissão ele não existe', async () => {
    viewport.set(330)
    open()
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    await click(screen.getByRole('menuitem', { name: 'Excluir página' }))
    expect(screen.getByRole('alertdialog')).toBeTruthy()
    cleanup()
    open('s2')
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    expect(screen.queryByRole('menuitem', { name: /Excluir/ })).toBeNull()
  })

  it('o nome "Dashboard" continua acessível mesmo escondido em tela estreita', () => {
    viewport.set(320)
    open()
    const back = screen.getByRole('button', { name: /Dashboard/ })
    expect(back.querySelector('.max-\\[400px\\]\\:sr-only')).toBeTruthy()
  })

  it('no celular os botões da capa ficam um sobre o outro, longe do ícone', () => {
    viewport.set(320)
    open()
    const group = screen.getByRole('button', { name: 'Trocar capa' }).parentElement!
    expect(group.className).toContain('flex-col')
    expect(group.className).toContain('min-[480px]:flex-row')
    expect(group.className).toContain('items-end')
  })

  it('axe: menu de inserir aberto em tela pequena e "Mais ações" aberto', async () => {
    viewport.set(320)
    open()
    await openMenu()
    expect(await violations()).toEqual([])
    await fireEvent.mouseDown(document.body)
    await click(screen.getByRole('button', { name: 'Mais ações' }))
    expect(await violations()).toEqual([])
  })
})

describe('Editor — cliques que não podem ser engolidos, e menu sempre para baixo', () => {
  it('a linha do ícone deixa o clique passar para a capa, e só o que é dela recebe clique', () => {
    open()
    const row = screen.getByTestId('icon-row')
    expect(row.className).toContain('pointer-events-none')
    expect(screen.getByRole('button', { name: 'Trocar ícone da página' }).className).toContain('pointer-events-auto')
    const controls = screen.getByRole('button', { name: 'Trocar capa' }).parentElement!
    const z = (c: string) => Number(/\bz-(\d+)\b/.exec(c)?.[1])
    expect(z(controls.className)).toBeGreaterThan(z(row.className))
  })

  it('"Trocar capa" abre e fecha o seletor, no desktop e no celular, sem e com ícone', async () => {
    for (const w of [1400, 390, 320]) {
      viewport.set(w)
      const { unmount } = open()
      await click(screen.getByRole('button', { name: 'Trocar capa' }))
      expect(screen.getByRole('dialog', { name: 'Escolher capa' })).toBeTruthy()
      await click(screen.getByRole('button', { name: 'Trocar capa' }))
      expect(screen.queryByRole('dialog', { name: 'Escolher capa' })).toBeNull()
      unmount()
    }
    ws.page('p0')!.icon = ''
    open()
    await click(screen.getByRole('button', { name: 'Trocar capa' }))
    expect(screen.getByRole('dialog', { name: 'Escolher capa' })).toBeTruthy()
  })

  it('o menu de blocos nunca abre para cima, e ganha altura que cabe na tela', async () => {
    for (const w of [1400, 320]) {
      viewport.set(w)
      const { unmount } = open()
      await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
      const menu = screen.getByRole('menu', { name: 'Inserir bloco' })
      expect(menu.className).toContain('top-full')
      expect(menu.className).not.toContain('bottom-full')
      const h = parseFloat(menu.style.maxHeight)
      expect(h).toBeGreaterThanOrEqual(160)
      expect(h).toBeLessThanOrEqual(384)
      unmount()
    }
  })

  it('com pouco espaço embaixo o menu encolhe e a página rola até mostrá-lo', async () => {
    const scroll = vi.fn()
    Element.prototype.scrollIntoView = scroll
    const original = Element.prototype.getBoundingClientRect
    Element.prototype.getBoundingClientRect = function () {
      return (this as HTMLElement).getAttribute('role') === 'menu' ? ({ top: window.innerHeight - 90, bottom: 0, left: 0, right: 0, width: 0, height: 0, x: 0, y: 0, toJSON() {} } as DOMRect) : original.call(this)
    }
    try {
      open()
      await click(screen.getByRole('button', { name: /Inserir bloco depois de Parágrafo 2/ }))
      await tick()
      const menu = screen.getByRole('menu', { name: 'Inserir bloco' })
      expect(parseFloat(menu.style.maxHeight)).toBe(160)
      expect(scroll).toHaveBeenCalledWith({ block: 'nearest' })
    } finally {
      Element.prototype.getBoundingClientRect = original
    }
  })
})

describe('Editor — arrastar blocos com o dedo (celular)', () => {
  let rectSpy: ReturnType<typeof vi.spyOn>
  const handle = (n: number) => screen.getByRole('button', { name: new RegExp(`Opções de .* ${n}$`) })
  const touch = (type: 'pointerDown' | 'pointerMove' | 'pointerUp' | 'pointerCancel', el: Element, y: number, pointerType = 'touch') =>
    fireEvent[type](el, { pointerId: 7, pointerType, clientY: y, clientX: 20, isPrimary: true })

  beforeEach(() => {
    viewport.set(390)
    // every block is a 100px band, so a finger at y lands in a known gap
    rectSpy = vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (this: Element) {
      const row = this.closest?.('[data-block-id]') as HTMLElement | null
      const rows = [...document.querySelectorAll('[data-block-id]')]
      if (this.hasAttribute('data-block-id')) {
        const top = rows.indexOf(this as HTMLElement) * 100
        return { top, bottom: top + 100, height: 100, left: 0, right: 300, width: 300, x: 0, y: top, toJSON() {} } as DOMRect
      }
      if (this.tagName === 'MAIN') return { top: 0, bottom: 600, height: 600, left: 0, right: 390, width: 390, x: 0, y: 0, toJSON() {} } as DOMRect
      void row
      return { top: 0, bottom: 0, height: 0, left: 0, right: 0, width: 0, x: 0, y: 0, toJSON() {} } as DOMRect
    })
  })
  afterEach(() => rectSpy.mockRestore())

  it('arrastar o ⠿ com o dedo move o bloco para onde o dedo soltou', async () => {
    open()
    const first = kindsOf()[0]
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerMove', h, 120)
    touch('pointerMove', h, 260)
    touch('pointerUp', h, 260)
    expect(kindsOf()[0]).not.toBe(first)
    expect(kindsOf()[2]).toBe(first)
  })

  it('arrastar para cima também funciona', async () => {
    open()
    const last = kindsOf().at(-1)
    const n = kindsOf().length
    const h = handle(n)
    touch('pointerDown', h, (n - 1) * 100 + 40)
    touch('pointerMove', h, 130)
    touch('pointerUp', h, 130)
    expect(kindsOf()[1]).toBe(last)
  })

  it('enquanto arrasta mostra onde vai cair e apaga o bloco de origem; ao soltar tudo some', () => {
    open()
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerMove', h, 230)
    expect(blockEls()[0].className).toContain('opacity-40')
    expect(blockEls().some((b) => /shadow-\[0_(-)?2px_0/.test(b.className))).toBe(true)
    touch('pointerUp', h, 230)
    expect(blockEls().some((b) => b.className.includes('opacity-40'))).toBe(false)
    expect(blockEls().some((b) => /shadow-\[0_(-)?2px_0/.test(b.className))).toBe(false)
  })

  it('um toque sem mover abre o menu do bloco e não move nada', async () => {
    open()
    const before = kindsOf().join()
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerUp', h, 40)
    await click(h)
    expect(screen.getByRole('menu', { name: 'Opções do bloco' })).toBeTruthy()
    expect(kindsOf().join()).toBe(before)
  })

  it('um tremor de menos de 6 px ainda é um toque', async () => {
    open()
    const before = kindsOf().join()
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerMove', h, 44)
    touch('pointerUp', h, 44)
    await click(h)
    expect(screen.getByRole('menu', { name: 'Opções do bloco' })).toBeTruthy()
    expect(kindsOf().join()).toBe(before)
  })

  it('o clique que vem logo depois de arrastar não abre o menu', async () => {
    open()
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerMove', h, 240)
    touch('pointerUp', h, 240)
    await click(h)
    expect(screen.queryByRole('menu', { name: 'Opções do bloco' })).toBeNull()
  })

  it('cancelar o gesto (o sistema tomou o dedo) não move nada', () => {
    open()
    const before = kindsOf().join()
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerMove', h, 300)
    touch('pointerCancel', h, 300)
    expect(kindsOf().join()).toBe(before)
    expect(blockEls().some((b) => b.className.includes('opacity-40'))).toBe(false)
  })

  it('soltar no mesmo lugar não muda nada', () => {
    open()
    const before = kindsOf().join()
    const h = handle(2)
    touch('pointerDown', h, 140)
    touch('pointerMove', h, 160)
    touch('pointerMove', h, 130)
    touch('pointerUp', h, 130)
    expect(kindsOf().join()).toBe(before)
  })

  it('outro dedo (outro pointerId) não interfere no gesto', () => {
    open()
    const before = kindsOf().join()
    const h = handle(1)
    touch('pointerDown', h, 40)
    fireEvent.pointerMove(h, { pointerId: 9, pointerType: 'touch', clientY: 300 })
    fireEvent.pointerUp(h, { pointerId: 9, pointerType: 'touch', clientY: 300 })
    expect(kindsOf().join()).toBe(before)
    touch('pointerUp', h, 40)
  })

  it('o mouse continua com o arrastar nativo: a alça é arrastável e o gesto de toque não começa', () => {
    open()
    const h = handle(1)
    expect(h.getAttribute('draggable')).toBe('true')
    touch('pointerDown', h, 40, 'mouse')
    touch('pointerMove', h, 300, 'mouse')
    touch('pointerUp', h, 300, 'mouse')
    expect(blockEls().some((b) => b.className.includes('opacity-40'))).toBe(false)
  })

  it('depois de um toque a alça deixa de ser "arrastável" do navegador, para ele não disputar o gesto', () => {
    open()
    const h = handle(1)
    touch('pointerDown', h, 40)
    expect(h.getAttribute('draggable')).toBe('false')
    touch('pointerUp', h, 40)
    touch('pointerDown', h, 40, 'mouse')
    expect(h.getAttribute('draggable')).toBe('true')
    touch('pointerUp', h, 40, 'mouse')
  })

  it('a alça não deixa a página rolar sob o dedo e é maior em tela de toque', () => {
    open()
    const cls = handle(1).className
    expect(cls).toContain('touch-none')
    expect(cls).toContain('[@media(pointer:coarse)]:size-10')
  })

  it('perto da borda de baixo a página rola sozinha enquanto o dedo segura', () => {
    const frames: FrameRequestCallback[] = []
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => (frames.push(cb), frames.length))
    open()
    const main = document.querySelector('main')!
    main.scrollTop = 100
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerMove', h, 590)
    frames.shift()!(0)
    expect(main.scrollTop).toBeGreaterThan(100)
    touch('pointerMove', h, 5)
    const before = main.scrollTop
    frames.shift()!(0)
    expect(main.scrollTop).toBeLessThan(before)
    touch('pointerUp', h, 5)
    expect(frames.length).toBeGreaterThanOrEqual(0)
    raf.mockRestore()
  })

  it('sem permissão para mexer nos blocos não há alça nem gesto', () => {
    open('s2')
    expect(screen.queryByRole('button', { name: /Opções de/ })).toBeNull()
  })

  it('axe: durante o arrasto', async () => {
    open()
    const h = handle(1)
    touch('pointerDown', h, 40)
    touch('pointerMove', h, 230)
    expect(await violations()).toEqual([])
    touch('pointerUp', h, 230)
  })
})

describe('Editor — arrastar colunas e linhas da tabela com o dedo', () => {
  let rectSpy: ReturnType<typeof vi.spyOn>
  const grip = (name: string) => screen.getByRole('button', { name })
  const finger = (type: 'pointerDown' | 'pointerMove' | 'pointerUp' | 'pointerCancel', el: Element, x: number, y: number, pointerType = 'touch') =>
    fireEvent[type](el, { pointerId: 3, pointerType, clientX: x, clientY: y, isPrimary: true })
  const labels = () => [1, 2, 3].map((n) => (screen.getByLabelText(`Nome da coluna ${n}`) as HTMLInputElement).value)
  const firstColumn = () => [1, 2, 3].map((n) => (screen.getByLabelText(new RegExp(`, linha ${n}$`), { selector: '[data-cell$="-0"]' }) as HTMLInputElement).value)

  beforeEach(() => {
    viewport.set(390)
    // columns are 100px wide bands, rows 50px tall, so a finger at (x, y) lands in a known gap
    rectSpy = vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (this: Element) {
      const box = (left: number, top: number, w: number, h: number) => ({ left, top, right: left + w, bottom: top + h, width: w, height: h, x: left, y: top, toJSON() {} }) as DOMRect
      if (this.matches('thead th[data-col]')) return box([...document.querySelectorAll('thead th[data-col]')].indexOf(this) * 100, 0, 100, 40)
      if (this.matches('tbody tr')) return box(0, [...document.querySelectorAll('tbody tr')].indexOf(this) * 50, 300, 50)
      if (this.matches('.overflow-x-auto')) return box(0, 0, 300, 200)
      if (this.tagName === 'MAIN') return box(0, 0, 390, 600)
      return box(0, 0, 0, 0)
    })
  })
  afterEach(() => rectSpy.mockRestore())

  it('arrastar a alça da coluna com o dedo muda a ordem das colunas', () => {
    open()
    expect(labels()).toEqual(['Frente', 'Responsável', 'Prazo'])
    const g = grip('Mover coluna Frente')
    finger('pointerDown', g, 10, 20)
    finger('pointerMove', g, 120, 20)
    finger('pointerMove', g, 260, 20)
    finger('pointerUp', g, 260, 20)
    expect(labels()).toEqual(['Responsável', 'Prazo', 'Frente'])
  })

  it('e de volta, da direita para a esquerda', () => {
    open()
    const g = grip('Mover coluna Prazo')
    finger('pointerDown', g, 290, 20)
    finger('pointerMove', g, 150, 20)
    finger('pointerMove', g, 20, 20)
    finger('pointerUp', g, 20, 20)
    expect(labels()).toEqual(['Prazo', 'Frente', 'Responsável'])
  })

  it('arrastar a alça da linha com o dedo muda a ordem das linhas', () => {
    open()
    expect(firstColumn()).toEqual(['Conciliação', 'Contratos', 'Relatório do conselho'])
    const g = grip('Mover linha 1')
    finger('pointerDown', g, 10, 10)
    finger('pointerMove', g, 10, 80)
    finger('pointerMove', g, 10, 140)
    finger('pointerUp', g, 10, 140)
    expect(firstColumn()).toEqual(['Contratos', 'Relatório do conselho', 'Conciliação'])
  })

  it('uma coluna não vira linha: cada gesto só vale no seu eixo', () => {
    open()
    const g = grip('Mover coluna Frente')
    finger('pointerDown', g, 10, 20)
    finger('pointerMove', g, 12, 300)
    finger('pointerUp', g, 12, 300)
    expect(labels()).toEqual(['Frente', 'Responsável', 'Prazo'])
  })

  it('mostra onde vai cair e apaga o que está sendo arrastado; ao soltar tudo some', () => {
    open()
    const g = grip('Mover coluna Frente')
    finger('pointerDown', g, 10, 20)
    finger('pointerMove', g, 160, 20)
    const heads = [...document.querySelectorAll('thead th[data-col]')]
    expect(heads[0].className).toContain('opacity-40')
    expect(heads.some((h) => /shadow-\[inset_(-)?2px_0_0/.test(h.className))).toBe(true)
    finger('pointerUp', g, 160, 20)
    expect([...document.querySelectorAll('thead th[data-col]')].some((h) => h.className.includes('opacity-40'))).toBe(false)
  })

  it('um toque, um tremor ou um cancelamento não movem nada', () => {
    open()
    const g = grip('Mover coluna Frente')
    finger('pointerDown', g, 10, 20)
    finger('pointerUp', g, 10, 20)
    finger('pointerDown', g, 10, 20)
    finger('pointerMove', g, 14, 22)
    finger('pointerUp', g, 14, 22)
    finger('pointerDown', g, 10, 20)
    finger('pointerMove', g, 280, 20)
    finger('pointerCancel', g, 280, 20)
    expect(labels()).toEqual(['Frente', 'Responsável', 'Prazo'])
    expect([...document.querySelectorAll('thead th[data-col]')].some((h) => h.className.includes('opacity-40'))).toBe(false)
  })

  it('o mouse segue com o arrastar nativo; depois de um toque a alça deixa de ser arrastável nativa', () => {
    open()
    const g = grip('Mover coluna Frente')
    expect(g.getAttribute('draggable')).toBe('true')
    finger('pointerDown', g, 10, 20, 'mouse')
    finger('pointerMove', g, 280, 20, 'mouse')
    finger('pointerUp', g, 280, 20, 'mouse')
    expect(labels()).toEqual(['Frente', 'Responsável', 'Prazo'])
    finger('pointerDown', g, 10, 20)
    expect(g.getAttribute('draggable')).toBe('false')
    finger('pointerUp', g, 10, 20)
    finger('pointerDown', g, 10, 20, 'mouse')
    expect(g.getAttribute('draggable')).toBe('true')
  })

  it('as alças não deixam a página rolar sob o dedo e são maiores em tela de toque', () => {
    open()
    for (const name of ['Mover coluna Frente', 'Mover linha 1']) {
      expect(grip(name).className).toContain('touch-none')
      expect(grip(name).className).toContain('[@media(pointer:coarse)]:size-9')
    }
  })

  it('perto das bordas a tabela rola sozinha: para os lados com colunas, para baixo com linhas', () => {
    const frames: FrameRequestCallback[] = []
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => (frames.push(cb), frames.length))
    open()
    const box = document.querySelector<HTMLElement>('.overflow-x-auto')!
    box.scrollLeft = 50
    const g = grip('Mover coluna Frente')
    finger('pointerDown', g, 10, 20)
    finger('pointerMove', g, 295, 20)
    frames.shift()!(0)
    expect(box.scrollLeft).toBeGreaterThan(50)
    finger('pointerUp', g, 295, 20)

    const main = document.querySelector('main')!
    main.scrollTop = 100
    const r = grip('Mover linha 1')
    finger('pointerDown', r, 10, 10)
    finger('pointerMove', r, 10, 595)
    frames.shift()!(0)
    expect(main.scrollTop).toBeGreaterThan(100)
    finger('pointerUp', r, 10, 595)
    raf.mockRestore()
  })

  it('sem permissão para mexer em tabelas as alças ficam desligadas e o gesto não faz nada', () => {
    open('s3')
    expect(screen.queryByRole('button', { name: /Mover (coluna|linha)/ })).toBeNull()
  })

  it('axe: durante o arrasto de uma coluna', async () => {
    open()
    const g = grip('Mover coluna Frente')
    finger('pointerDown', g, 10, 20)
    finger('pointerMove', g, 160, 20)
    expect(await violations()).toEqual([])
    finger('pointerUp', g, 160, 20)
  })
})

describe('Editor — títulos de três tamanhos, listas, sumário, link e destaques', () => {
  const insert = async (name: RegExp | string, after = /Inserir bloco depois de Parágrafo 2/) => {
    await click(screen.getByRole('button', { name: after }))
    await click(screen.getByRole('menuitem', { name }))
  }
  const setBlocks = (blocks: Block[], id = 'p5') => {
    ws.contentOf(id)
    ws.page(id)!.content = blocks
  }
  const item = (type: 'bullet' | 'numbered', id: string, text = '', indent = 0): Block => ({ id, type, text, indent })

  it('Título 1, 2 e 3 do menu criam títulos de tamanhos diferentes', async () => {
    open('p5')
    for (const [name, level, size] of [[/^Título 1$/, 1, 'text-3xl'], [/^Título 2$/, 2, 'text-2xl'], [/^Título 3$/, 3, 'text-xl']] as const) {
      await type(screen.getByLabelText('Nova linha'), '/')
      await click(screen.getByRole('menuitem', { name }))
      const made = ws.page('p5')!.content!.at(-1) as { type: string; level?: number }
      expect(made.type).toBe('heading')
      expect(made.level ?? 2).toBe(level)
      await waitFor(() => expect(document.querySelector('[data-rich]')!.className).toContain(size))
    }
  })

  it('a lista com marcadores mostra o marcador, e Enter faz outro item e leva o cursor a ele', async () => {
    open('p5')
    await type(screen.getByLabelText('Nova linha'), '/')
    await click(screen.getByRole('menuitem', { name: /Lista com marcadores/ }))
    const { inst, dom } = await rich('Item de lista')
    await put(inst, 'primeiro')
    await keys(dom, 'Enter')
    await fireEvent.blur(dom)
    await tick()
    const items = ws.page('p5')!.content!.filter((b) => b.type === 'bullet')
    expect(items).toHaveLength(2)
    expect(screen.getAllByRole('group').filter((g) => g.getAttribute('aria-label')?.startsWith('Item de lista')).map((g) => g.querySelector('span.select-none')!.textContent === '•')).toEqual([true, true])
  })

  it('a lista numerada conta 1, 2, 3 e recomeça depois de um texto', async () => {
    setBlocks([item('numbered', 'a', 'um'), item('numbered', 'b', 'dois'), { id: 'p', type: 'paragraph', text: 'quebra' }, item('numbered', 'c', 'tres')])
    open('p5')
    const marks = screen.getAllByRole('group').filter((g) => g.getAttribute('aria-label')?.startsWith('Item numerado')).map((g) => g.querySelector('span.select-none')!.textContent)
    expect(marks).toEqual(['1.', '2.', '1.'])
  })

  it('a numeração acompanha quando se muda a ordem', async () => {
    setBlocks([item('numbered', 'a', 'um'), item('numbered', 'b', 'dois'), { id: 'p', type: 'paragraph', text: 'meio' }])
    open('p5')
    ws.page('p5')!.content!.splice(1, 0, ws.page('p5')!.content!.splice(2, 1)[0])
    await tick()
    const marks = screen.getAllByRole('group').filter((g) => g.getAttribute('aria-label')?.startsWith('Item numerado')).map((g) => g.querySelector('span.select-none')!.textContent)
    expect(marks).toEqual(['1.', '1.'])
  })

  it('Tab recua o item e Shift+Tab traz de volta; fora de uma lista Tab não faz nada de especial', async () => {
    setBlocks([item('bullet', 'a', 'item'), { id: 'p', type: 'paragraph', text: 'texto' }])
    open('p5')
    const { dom } = await rich('Item de lista')
    expect(await keys(dom, 'Tab')).toBe(false)
    await tick()
    expect((ws.page('p5')!.content![0] as { indent: number }).indent).toBe(1)
    expect(document.querySelector<HTMLElement>('[data-block-id="a"] [style*="padding-left"]')!.style.paddingLeft).toBe('1.75rem')
    await keys(dom, 'Tab', { shiftKey: true })
    expect((ws.page('p5')!.content![0] as { indent: number }).indent).toBe(0)
    await fireEvent.blur(dom)
    const para = await rich('Parágrafo')
    expect(await keys(para.dom, 'Tab')).toBe(true)
  })

  it('Enter e Backspace num item vazio saem da lista: primeiro um nível, depois viram texto', async () => {
    setBlocks([item('bullet', 'a', '', 1)])
    open('p5')
    const { dom } = await rich('Item de lista')
    await keys(dom, 'Enter')
    expect((ws.page('p5')!.content![0] as { indent: number }).indent).toBe(0)
    await keys(dom, 'Backspace')
    await waitFor(() => expect(ws.page('p5')!.content![0].type).toBe('paragraph'))
    // the block was not deleted: Backspace on an empty list item only ends the list
    expect(ws.page('p5')!.content).toHaveLength(1)
  })

  it('"# ", "## ", "### ", "- ", "1. " e "> " num parágrafo vazio viram título, lista e citação', async () => {
    const cases: [string, string, number | undefined][] = [['# ', 'heading', 1], ['## ', 'heading', undefined], ['### ', 'heading', 3], ['- ', 'bullet', undefined], ['* ', 'bullet', undefined], ['1. ', 'numbered', undefined], ['> ', 'quote', undefined]]
    for (const [typed, kind, level] of cases) {
      cleanup()
      setBlocks([{ id: 'p', type: 'paragraph', text: '' }], 'p5')
      open('p5')
      const { inst } = await rich()
      await put(inst, typed)
      await waitFor(() => expect(ws.page('p5')!.content![0].type, typed).toBe(kind))
      expect((ws.page('p5')!.content![0] as { text: string; level?: number }).text).toBe('')
      if (kind === 'heading') expect((ws.page('p5')!.content![0] as { level?: number }).level, typed).toBe(level)
      // the caret is back in the new field, ready to write
      await waitFor(() => expect(document.querySelector('[data-rich]')).not.toBeNull())
    }
  })

  it('os atalhos só valem no começo de um parágrafo vazio: nada muda no meio de um texto, num título ou numa citação', async () => {
    setBlocks([{ id: 'p', type: 'paragraph', text: '' }, { id: 'h', type: 'heading', text: '' }, { id: 'q', type: 'quote', text: '' }])
    open('p5')
    const para = await rich('Parágrafo')
    await put(para.inst, 'abc - ')
    expect(ws.page('p5')!.content![0].type).toBe('paragraph')
    await put(para.inst, '-')
    expect(ws.page('p5')!.content![0].type).toBe('paragraph')
    await fireEvent.blur(para.dom)
    const h = await rich('Título de seção')
    await put(h.inst, '- ')
    expect(ws.page('p5')!.content![1].type).toBe('heading')
    await fireEvent.blur(h.dom)
    const q = await rich('Citação')
    await put(q.inst, '1. ')
    expect(ws.page('p5')!.content![2].type).toBe('quote')
  })

  it('o sumário lista os títulos com recuo por tamanho, e clicar leva até o título', async () => {
    setBlocks([
      { id: 'h1', type: 'heading', text: 'Grande', level: 1 },
      { id: 'h2', type: 'heading', text: 'Médio' },
      { id: 'h3', type: 'heading', text: 'Pequeno', level: 3 },
      { id: 't', type: 'toc' },
    ])
    const scrolled: string[] = []
    Element.prototype.scrollIntoView = function (this: Element) {
      scrolled.push(this.getAttribute('data-block-id') ?? '')
    }
    open('p5')
    const toc = within(screen.getByRole('navigation', { name: 'Sumário da página' }))
    expect(toc.getAllByRole('button').map((b) => b.textContent)).toEqual(['Grande', 'Médio', 'Pequeno'])
    expect(toc.getAllByRole('listitem').map((li) => (li as HTMLElement).style.paddingLeft)).toEqual(['0rem', '1.1rem', '2.2rem'])
    await click(toc.getByRole('button', { name: 'Pequeno' }))
    expect(scrolled).toContain('h3')
  })

  it('o sumário acompanha o que se escreve e avisa quando ainda não há títulos', async () => {
    setBlocks([{ id: 't', type: 'toc' }, { id: 'h', type: 'heading', text: 'Antes' }])
    open('p5')
    const { inst } = await rich('Título de seção')
    await put(inst, 'Depois')
    expect(within(screen.getByRole('navigation', { name: 'Sumário da página' })).getAllByRole('button').map((b) => b.textContent)).toEqual(['Depois'])
    cleanup()
    setBlocks([{ id: 't', type: 'toc' }])
    open('p5')
    expect(screen.getByRole('navigation', { name: 'Sumário da página' }).textContent).toContain('Os títulos de seção aparecem aqui')
  })

  it('o painel "Nesta página" recua os títulos menores', () => {
    setBlocks([{ id: 'h1', type: 'heading', text: 'Grande', level: 1 }, { id: 'h3', type: 'heading', text: 'Pequeno', level: 3 }])
    open('p5')
    const list = within(screen.getByRole('complementary', { name: 'Painel da página' }))
    const rows = list.getAllByRole('listitem').filter((li) => ['Grande', 'Pequeno'].includes(li.textContent!.trim()))
    expect(rows.map((li) => (li as HTMLElement).style.paddingLeft)).toEqual(['0rem', '1.8rem'])
  })

  it('o link: pede o endereço, recusa o perigoso, e depois mostra um cartão que abre em outra aba com segurança', async () => {
    open('p5')
    await type(screen.getByLabelText('Nova linha'), '/')
    await click(screen.getByRole('menuitem', { name: /^Link$/ }))
    const url = (await screen.findByLabelText('Endereço do link')) as HTMLInputElement
    await type(url, 'javascript:alert(1)')
    await fireEvent.submit(url.closest('form')!)
    expect(toast.message).toContain('Endereço inválido')
    expect(ws.page('p5')!.content!.at(-1)).toMatchObject({ type: 'bookmark', url: '' })
    await type(url, 'exemplo.com/pagina')
    await type(screen.getByLabelText('Título do link (opcional)'), 'Meu site')
    await fireEvent.submit(url.closest('form')!)
    const card = (await screen.findByRole('link', { name: /Abrir Meu site/ })) as HTMLAnchorElement
    expect(card.href).toBe('https://exemplo.com/pagina')
    expect(card.target).toBe('_blank')
    expect(card.rel).toContain('noopener')
    expect(card.rel).toContain('noreferrer')
    // edit it again
    await click(screen.getByRole('button', { name: 'Editar' }))
    expect((screen.getByLabelText('Endereço do link') as HTMLInputElement).value).toBe('https://exemplo.com/pagina')
  })

  it('um link sem título mostra o site; numa página só de leitura não há como editar', async () => {
    setBlocks([{ id: 'b', type: 'bookmark', url: 'https://www.exemplo.com/x', title: '' }], 's2')
    open('s2')
    expect(screen.getByRole('link', { name: 'Abrir exemplo.com' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Editar' })).toBeNull()
    cleanup()
    setBlocks([{ id: 'b', type: 'bookmark', url: '', title: '' }], 's2')
    open('s2')
    expect(screen.queryByLabelText('Endereço do link')).toBeNull()
    expect(screen.getByText('Link sem endereço')).toBeTruthy()
  })

  it('o destaque troca de tom pelo menu do bloco, muda a cor e o ícone, e o tom padrão volta a não guardar nada', async () => {
    setBlocks([{ id: 'c', type: 'callout', text: 'cuidado' }])
    open('p5')
    const group = () => screen.getByRole('group', { name: /Destaque 1 de 1/ })
    expect(group().textContent).toContain('💡')
    await click(screen.getByRole('button', { name: 'Opções de Destaque 1' }))
    await click(screen.getByRole('menuitemradio', { name: 'Tom Atenção' }))
    expect(ws.page('p5')!.content![0]).toMatchObject({ tone: 'warning' })
    expect(group().textContent).toContain('⚠️')
    expect(drawn('Destaque').className).toContain('bg-tag-gold/10')
    await click(screen.getByRole('button', { name: 'Opções de Destaque 1' }))
    expect(screen.getByRole('menuitemradio', { name: 'Tom Atenção' }).getAttribute('aria-checked')).toBe('true')
    await click(screen.getByRole('menuitemradio', { name: 'Tom Nota' }))
    expect('tone' in ws.page('p5')!.content![0]).toBe(false)
  })

  it('"Transformar em" oferece os três títulos e as listas, e esconde o tipo atual', async () => {
    setBlocks([{ id: 'p', type: 'paragraph', text: 'palavras' }])
    open('p5')
    await click(screen.getByRole('button', { name: 'Opções de Parágrafo 1' }))
    const names = screen.getAllByRole('menuitem').map((m) => m.textContent!.trim())
    expect(names).toEqual(expect.arrayContaining(['Título 1', 'Título 2', 'Título 3', 'Título 1 com toggle', 'Lista com marcadores', 'Lista numerada']))
    expect(names).not.toContain('Texto')
    await click(screen.getByRole('menuitem', { name: /^Título 3$/ }))
    expect(ws.page('p5')!.content![0]).toMatchObject({ type: 'heading', level: 3, text: 'palavras' })
    await click(screen.getByRole('button', { name: 'Opções de Título de seção 1' }))
    const again = screen.getAllByRole('menuitem').map((m) => m.textContent!.trim())
    expect(again).toContain('Título 1')
    expect(again).not.toContain('Título 3')
  })

  it('numa página só de leitura os itens de lista e títulos são só texto', async () => {
    setBlocks([item('bullet', 'a', 'item'), { id: 'h', type: 'heading', text: 'Título', level: 1 }], 's2')
    open('s2')
    drawn('Item de lista').focus()
    drawn('Título de seção').focus()
    await tick()
    noEditor()
    expect(screen.queryByRole('button', { name: /Opções de/ })).toBeNull()
  })

  it('axe: a página com todos os blocos novos, e o menu de inserir com as novas opções', async () => {
    setBlocks([
      { id: 'h1', type: 'heading', text: 'Grande', level: 1 },
      { id: 't', type: 'toc' },
      item('bullet', 'a', 'item', 1),
      item('numbered', 'n', 'um'),
      { id: 'b', type: 'bookmark', url: 'https://exemplo.com', title: 'Exemplo' },
      { id: 'c', type: 'callout', text: 'aviso', tone: 'danger' },
    ])
    open('p5')
    expect(await violations()).toEqual([])
    await click(screen.getAllByRole('button', { name: /Inserir bloco depois/ })[0])
    expect(await violations()).toEqual([])
  })

  it('uma página enorme de itens de lista continua leve: 500 itens numerados, contagem certa', () => {
    setBlocks(Array.from({ length: 500 }, (_, i) => item('numbered', `n${i}`, `item ${i}`, i % 3)))
    const t0 = performance.now()
    open('p5')
    expect(performance.now() - t0).toBeLessThan(4000)
    expect(document.querySelectorAll('[data-block-id]').length).toBeGreaterThan(100)
  })
})

describe('Editor — título com toggle', () => {
  const setBlocks = (blocks: Block[]) => {
    ws.contentOf('p5')
    ws.page('p5')!.content = blocks
  }

  it('o menu cria um título de cada tamanho que abre e fecha um texto', async () => {
    open('p5')
    for (const [name, level] of [[/Título 1 com toggle/, 1], [/Título 2 com toggle/, 2], [/Título 3 com toggle/, 3]] as const) {
      await type(screen.getByLabelText('Nova linha'), '/')
      await click(screen.getByRole('menuitem', { name }))
      const made = ws.page('p5')!.content!.at(-1) as { type: string; level?: number; toggle?: boolean; body?: string }
      expect(made).toMatchObject({ type: 'heading', toggle: true, body: '' })
      expect(made.level ?? 2).toBe(level)
    }
    expect(screen.getAllByRole('button', { name: 'Abrir toggle' })).toHaveLength(3)
  })

  it('Enter no título abre o texto de baixo e leva o cursor a ele; a seta fecha de novo', async () => {
    setBlocks([{ id: 'h', type: 'heading', text: 'Seção', level: 1, toggle: true, body: '' }])
    open('p5')
    expect(screen.queryByLabelText('Conteúdo do toggle')).toBeNull()
    const { dom } = await rich('Título de seção')
    await keys(dom, 'Enter')
    const body = (await screen.findByLabelText('Conteúdo do toggle')) as HTMLTextAreaElement
    await waitFor(() => expect(document.activeElement).toBe(body))
    await type(body, 'escondido')
    expect(ws.page('p5')!.content![0]).toMatchObject({ text: 'Seção', body: 'escondido' })
    await click(screen.getByRole('button', { name: 'Fechar toggle' }))
    expect(screen.queryByLabelText('Conteúdo do toggle')).toBeNull()
  })

  it('o título com toggle aparece no sumário e conta as palavras do texto escondido', () => {
    setBlocks([{ id: 'h', type: 'heading', text: 'Seção', toggle: true, body: 'uma duas três' }])
    open('p5')
    const side = within(screen.getByRole('complementary', { name: 'Painel da página' }))
    expect(side.getAllByRole('listitem').some((li) => li.textContent!.trim() === 'Seção')).toBe(true)
    expect(Number(side.getByTestId('stat-words').textContent)).toBe(4)
  })

  it('"Transformar em" liga e desliga o toggle do título sem perder o texto', async () => {
    setBlocks([{ id: 'h', type: 'heading', text: 'Seção', level: 3 }])
    open('p5')
    await click(screen.getByRole('button', { name: 'Opções de Título de seção 1' }))
    await click(screen.getByRole('menuitem', { name: 'Título 3 com toggle' }))
    expect(ws.page('p5')!.content![0]).toMatchObject({ type: 'heading', level: 3, toggle: true, body: '', text: 'Seção' })
    await click(screen.getByRole('button', { name: 'Opções de Título de seção 1' }))
    const names = screen.getAllByRole('menuitem').map((m) => m.textContent!.trim())
    expect(names).not.toContain('Título 3 com toggle')
    expect(names).toContain('Título 3')
    await click(screen.getByRole('menuitem', { name: /^Título 3$/ }))
    expect('toggle' in ws.page('p5')!.content![0]).toBe(false)
  })

  it('exporta com <details> e o tamanho do título', async () => {
    const { pageToHtml, pageToMarkdown, pageToText } = await import('../lib/stores/transfer')
    setBlocks([{ id: 'h', type: 'heading', text: 'Seção <b>', level: 1, toggle: true, body: 'dentro **forte**' }])
    const p = ws.page('p5')!
    expect(pageToMarkdown(p, [])).toContain('<details><summary><h1>Seção &lt;b&gt;</h1></summary>\n\ndentro **forte**\n\n</details>')
    expect(pageToHtml(p, [])).toContain('<details><summary><h1>Seção &lt;b&gt;</h1></summary><p>dentro <strong>forte</strong></p></details>')
    expect(pageToText(p, [])).toContain('SEÇÃO <B>\ndentro **forte**')
  })

  it('numa página só de leitura o título com toggle abre e fecha, mas não se escreve', async () => {
    ws.contentOf('s2')
    ws.page('s2')!.content = [{ id: 'h', type: 'heading', text: 'Seção', toggle: true, body: 'texto' }]
    open('s2')
    await click(screen.getByRole('button', { name: 'Abrir toggle' }))
    expect((screen.getByLabelText('Conteúdo do toggle') as HTMLTextAreaElement).readOnly).toBe(true)
    drawn('Título de seção').focus()
    await tick()
    noEditor()
  })
})

describe('Editor — vídeo, áudio, PDF e link para página', () => {
  const setBlocks = (blocks: Block[], id = 'p5') => {
    ws.contentOf(id)
    ws.page(id)!.content = blocks
  }

  it('o vídeo pede o endereço, recusa o que não é http(s), e depois mostra um player que só carrega ao tocar', async () => {
    open('p5')
    await type(screen.getByLabelText('Nova linha'), '/')
    await click(screen.getByRole('menuitem', { name: /Vídeo/ }))
    const url = (await screen.findByLabelText('Endereço do link')) as HTMLInputElement
    await type(url, 'ana@exemplo.com')
    await fireEvent.submit(url.closest('form')!)
    expect(toast.message).toMatch(/http ou https/)
    expect(ws.page('p5')!.content!.at(-1)).toMatchObject({ type: 'video', url: '' })
    await type(url, 'https://exemplo.com/aula.mp4')
    await type(screen.getByLabelText('Título do link (opcional)'), 'Aula 1')
    await fireEvent.submit(url.closest('form')!)
    const video = (await screen.findByLabelText('Vídeo: Aula 1')) as HTMLVideoElement
    expect(video.tagName).toBe('VIDEO')
    expect(video.getAttribute('preload')).toBe('none')
    expect(video.getAttribute('src')).toBe('https://exemplo.com/aula.mp4')
    expect(video.hasAttribute('autoplay')).toBe(false)
  })

  it('um endereço de player (YouTube) não vira player: vira link para abrir em outra aba', async () => {
    setBlocks([{ id: 'v', type: 'video', url: 'https://www.youtube.com/watch?v=abc', title: 'Vídeo do canal' }])
    open('p5')
    expect(document.querySelector('video')).toBeNull()
    expect(screen.getByText(/não é um arquivo direto/)).toBeTruthy()
    const link = screen.getByRole('link', { name: /Abrir vídeo Vídeo do canal/ }) as HTMLAnchorElement
    expect(link.target).toBe('_blank')
    expect(link.rel).toContain('noopener')
  })

  it('o áudio é um player sem carregar nada antes de tocar, e um arquivo que falha vira link', async () => {
    setBlocks([{ id: 'a', type: 'audio', url: 'https://exemplo.com/som.mp3', title: '' }])
    open('p5')
    const audio = document.querySelector('audio')!
    expect(audio.getAttribute('preload')).toBe('none')
    expect(audio.getAttribute('aria-label')).toBe('Áudio: som.mp3')
    await fireEvent.error(audio)
    await tick()
    expect(document.querySelector('audio')).toBeNull()
    expect(screen.getByText(/Não foi possível carregar/)).toBeTruthy()
  })

  it('o PDF é um cartão que abre em outra aba; nunca embute o arquivo', () => {
    setBlocks([{ id: 'd', type: 'pdf', url: 'https://exemplo.com/docs/Manual%20de%20uso.pdf', title: '' }])
    open('p5')
    expect(document.querySelector('iframe, embed, object')).toBeNull()
    const link = screen.getByRole('link', { name: /Abrir pdf Manual de uso\.pdf/ }) as HTMLAnchorElement
    expect(link.href).toBe('https://exemplo.com/docs/Manual%20de%20uso.pdf')
    expect(link.target).toBe('_blank')
  })

  it('numa página só de leitura a mídia toca, mas não se edita', () => {
    setBlocks([{ id: 'v', type: 'video', url: 'https://exemplo.com/v.mp4', title: 'Aula' }, { id: 'e', type: 'video', url: '', title: '' }], 's2')
    open('s2')
    expect(document.querySelector('video')).not.toBeNull()
    expect(screen.queryByRole('button', { name: 'Editar' })).toBeNull()
    expect(screen.queryByLabelText('Endereço do link')).toBeNull()
    expect(screen.getByText('Vídeo sem endereço')).toBeTruthy()
  })

  it('o link para página busca por nome, liga e abre a página; não oferece a própria, a da lixeira nem a do cofre', async () => {
    const onopen = vi.fn()
    setBlocks([{ id: 'l', type: 'pagelink', pageId: '', title: '' }])
    render(Editor, { ws, id: 'p5', onback: vi.fn(), onopen })
    const list = () => screen.queryAllByRole('button', { name: /^Ligar à página/ }).map((b) => b.getAttribute('aria-label'))
    expect(list().length).toBeGreaterThan(1)
    expect(list().length).toBeLessThanOrEqual(8)
    expect(list().join()).not.toContain(ws.page('p5')!.title)
    expect(list().join()).not.toContain(ws.pages.find((p) => p.locked)!.title)
    ws.trash('p1')
    await type(screen.getByLabelText('Buscar página para ligar'), 'encerramento do trimestre')
    expect(list()).toEqual(['Ligar à página Rotina de encerramento do trimestre'])
    await click(screen.getByRole('button', { name: /Ligar à página Rotina/ }))
    expect(ws.page('p5')!.content![0]).toMatchObject({ type: 'pagelink', pageId: 'p0', title: 'Rotina de encerramento do trimestre' })
    await click(await screen.findByRole('button', { name: 'Abrir a página Rotina de encerramento do trimestre' }))
    expect(onopen).toHaveBeenCalledWith('p0')
  })

  it('o cartão mostra o nome atual da página, e o aviso certo quando ela some, vai para a lixeira ou para o cofre', async () => {
    setBlocks([{ id: 'l', type: 'pagelink', pageId: 'p0', title: 'Nome antigo' }])
    open('p5')
    expect(screen.getByRole('button', { name: /Abrir a página Rotina de encerramento/ })).toBeTruthy()
    await waitFor(() => expect((ws.page('p5')!.content![0] as { title: string }).title).toBe('Rotina de encerramento do trimestre'))
    cleanup()
    ws.trash('p0')
    open('p5')
    expect(screen.queryByRole('button', { name: /Abrir a página/ })).toBeNull()
    expect(screen.getByText(/na lixeira/)).toBeTruthy()
    cleanup()
    ws.pages.splice(ws.pages.findIndex((p) => p.id === 'p0'), 1)
    open('p5')
    expect(screen.getByText(/página não encontrada/)).toBeTruthy()
    cleanup()
    const vault = ws.pages.find((p) => p.locked)!
    setBlocks([{ id: 'l', type: 'pagelink', pageId: vault.id, title: '' }])
    open('p5')
    expect(screen.getByText('Página do cofre')).toBeTruthy()
    expect(document.body.textContent).not.toContain(vault.title)
  })

  it('numa página só de leitura o link para página abre, mas não troca de destino', () => {
    setBlocks([{ id: 'l', type: 'pagelink', pageId: 'p0', title: 'Rotina' }], 's2')
    open('s2')
    expect(screen.getByRole('button', { name: /Abrir a página/ })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Trocar' })).toBeNull()
  })

  it('axe: a página com vídeo, áudio, PDF e link para página', async () => {
    setBlocks([
      { id: 'v', type: 'video', url: 'https://exemplo.com/v.mp4', title: 'Aula' },
      { id: 'a', type: 'audio', url: 'https://exemplo.com/a.mp3', title: 'Som' },
      { id: 'd', type: 'pdf', url: 'https://exemplo.com/d.pdf', title: 'Manual' },
      { id: 'l', type: 'pagelink', pageId: 'p0', title: 'Rotina' },
      { id: 'e', type: 'pagelink', pageId: '', title: '' },
    ])
    open('p5')
    expect(await violations()).toEqual([])
  })
})

describe('Editor — arquivos no servidor', () => {
  let server: FakeFiles
  beforeEach(() => {
    server = new FakeFiles()
    vi.mocked(fetch).mockImplementation(server.fetch as typeof fetch)
  })
  afterEach(() => {
    session.token = null
  })
  const signIn = () => (session.token = server.token)
  const setBlocks = (blocks: Block[], id = 'p5') => {
    ws.contentOf(id)
    ws.page(id)!.content = blocks
  }
  const pickFile = async (label: RegExp | string, file: File) => {
    const input = screen.getByLabelText(label) as HTMLInputElement
    await fireEvent.change(input, { target: { files: [file] } })
  }
  const until = (cond: () => boolean) => waitFor(() => expect(cond()).toBe(true))
  const doc = (name: string, size = 3000) => new File([patterned(size)], name)

  it('sem sessão o bloco Arquivo explica e não envia', async () => {
    setBlocks([{ id: 'f', type: 'file', fileId: '', name: '', size: 0, mime: '', level: 3 }])
    open('p5')
    expect(screen.getByText(/Entre em um servidor para enviar arquivos/)).toBeTruthy()
    await pickFile('Arraste um arquivo aqui ou clique para escolher', doc('a.txt'))
    expect(toast.message).toMatch(/Entre em um servidor/)
    expect(server.seen).toHaveLength(0)
  })

  it('escolher um arquivo mostra o andamento e depois o cartão com nome e tamanho', async () => {
    signIn()
    server.delay = 30
    setBlocks([{ id: 'f', type: 'file', fileId: '', name: '', size: 0, mime: '', level: 3 }])
    open('p5')
    await pickFile('Arraste um arquivo aqui ou clique para escolher', doc('relatorio.zip', 1_200_000))
    const bar = await screen.findByRole('progressbar', { name: 'Enviando relatorio.zip' })
    expect(bar.getAttribute('aria-valuemax')).toBe('100')
    await until(() => !!ws.page('p5')!.content!.find((b) => b.type === 'file' && b.fileId))
    expect(await screen.findByText('relatorio.zip')).toBeTruthy()
    expect(screen.getByText(/1\.2 MB · application\/zip/)).toBeTruthy()
    expect(screen.queryByRole('progressbar')).toBeNull()
  })

  it('o botão Cancelar para o envio e o bloco volta a pedir o arquivo', async () => {
    signIn()
    server.delay = 40
    setBlocks([{ id: 'f', type: 'file', fileId: '', name: '', size: 0, mime: '', level: 3 }])
    open('p5')
    await pickFile('Arraste um arquivo aqui ou clique para escolher', doc('a.bin', 2_000_000))
    await screen.findByRole('progressbar')
    await click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('progressbar')).toBeNull()
    expect(screen.getByLabelText('Arraste um arquivo aqui ou clique para escolher')).toBeTruthy()
    await new Promise((r) => setTimeout(r, 200))
    expect(server.files.size).toBe(0)
  })

  it('um envio que falha mostra o motivo, e dá para dispensar', async () => {
    signIn()
    server.quota = 10
    setBlocks([{ id: 'f', type: 'file', fileId: '', name: '', size: 0, mime: '', level: 3 }])
    open('p5')
    await pickFile('Arraste um arquivo aqui ou clique para escolher', doc('a.bin', 5000))
    const alert = await screen.findByRole('alert')
    expect(alert.textContent).toMatch(/espaço de arquivos/)
    await click(screen.getByRole('button', { name: 'Dispensar' }))
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('arquivo de documento baixa direto; arquivo desconhecido pede confirmação antes', async () => {
    signIn()
    const click_ = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    try {
      setBlocks([{ id: 'f', type: 'file', fileId: '', name: '', size: 0, mime: '', level: 3 }, { id: 'g', type: 'file', fileId: '', name: '', size: 0, mime: '', level: 3 }])
      open('p5')
      const pickers = screen.getAllByLabelText('Arraste um arquivo aqui ou clique para escolher')
      await fireEvent.change(pickers[0], { target: { files: [doc('notas.txt')] } })
      await until(() => !!(ws.page('p5')!.content![0] as { fileId: string }).fileId)
      await fireEvent.change(screen.getByLabelText('Arraste um arquivo aqui ou clique para escolher'), { target: { files: [doc('coisa.bin')] } })
      await until(() => !!(ws.page('p5')!.content![1] as { fileId: string }).fileId)
      await click(await screen.findByRole('button', { name: 'Baixar notas.txt' }))
      await until(() => click_.mock.calls.length === 1)
      expect(screen.queryByRole('alertdialog')).toBeNull()
      await click(screen.getByRole('button', { name: 'Baixar coisa.bin' }))
      const warn = await screen.findByRole('alertdialog', { name: 'Baixar arquivo desconhecido' })
      expect(warn.textContent).toMatch(/só se você confia/)
      expect(click_).toHaveBeenCalledTimes(1)
      await click(screen.getByRole('button', { name: 'Cancelar' }))
      expect(screen.queryByRole('alertdialog')).toBeNull()
      await click(screen.getByRole('button', { name: 'Baixar coisa.bin' }))
      await click(screen.getByRole('button', { name: 'Baixar mesmo assim' }))
      await until(() => click_.mock.calls.length === 2)
    } finally {
      click_.mockRestore()
    }
  })

  it('a imagem do servidor mostra o endereço assinado, e tenta um novo se o primeiro falhar', async () => {
    signIn()
    setBlocks([{ id: 'i', type: 'image', name: null, src: null }])
    open('p5')
    await pickFile('Arraste uma imagem aqui ou clique para escolher', doc('foto.png'))
    const img = (await screen.findByAltText('foto.png')) as HTMLImageElement
    expect(img.getAttribute('src')).toMatch(/^\/files\/f\d+\?exp=/)
    const before = server.seen.filter((r) => r.path.endsWith('/link')).length
    await fireEvent.error(img)
    await until(() => server.seen.filter((r) => r.path.endsWith('/link')).length === before + 1)
    // a second failure is not retried forever
    await fireEvent.error(img)
    await new Promise((r) => setTimeout(r, 30))
    expect(server.seen.filter((r) => r.path.endsWith('/link')).length).toBe(before + 1)
  })

  it('vídeo e áudio do servidor tocam do endereço assinado, sem baixar nada antes do play', async () => {
    signIn()
    setBlocks([{ id: 'v', type: 'video', url: '', title: '' }, { id: 'a', type: 'audio', url: '', title: '' }])
    open('p5')
    const inputs = screen.getAllByLabelText('…ou envie um arquivo daqui')
    await fireEvent.change(inputs[0], { target: { files: [doc('aula.mp4')] } })
    await until(() => !!(ws.page('p5')!.content![0] as { fileId?: string }).fileId)
    await fireEvent.change(screen.getByLabelText('…ou envie um arquivo daqui'), { target: { files: [doc('som.mp3')] } })
    await until(() => !!(ws.page('p5')!.content![1] as { fileId?: string }).fileId)
    const video = (await screen.findByLabelText('Vídeo: aula.mp4')) as HTMLVideoElement
    const audio = (await screen.findByLabelText('Áudio: som.mp3')) as HTMLAudioElement
    for (const el of [video, audio]) {
      expect(el.getAttribute('preload')).toBe('none')
      expect(el.hasAttribute('autoplay')).toBe(false)
      await until(() => /^\/files\/f\d+\?exp=/.test(el.getAttribute('src') ?? ''))
    }
    // the server's own addresses never leave the page: nothing but /files/ was asked for
    expect(server.seen.every((r) => r.path.startsWith('/files/'))).toBe(true)
  })

  it('um PDF do servidor abre pelo endereço assinado em outra aba', async () => {
    signIn()
    setBlocks([{ id: 'd', type: 'pdf', url: '', title: '' }])
    open('p5')
    await fireEvent.change(screen.getByLabelText('…ou envie um arquivo daqui'), { target: { files: [doc('manual.pdf')] } })
    const link = (await screen.findByRole('link', { name: /Abrir pdf manual\.pdf/ })) as HTMLAnchorElement
    await until(() => (link.getAttribute('href') ?? '').startsWith('/files/'))
    expect(link.target).toBe('_blank')
    expect(link.rel).toContain('noopener')
  })

  it('arrastar arquivos para a página cria um bloco para cada um, do tipo certo, e envia', async () => {
    signIn()
    open('p5')
    const before = ws.page('p5')!.content!.length
    const article = document.querySelector('article')!
    const files = [doc('foto.png'), doc('aula.mp4'), doc('notas.txt'), doc('coisa.bin')]
    await fireEvent.drop(article, { dataTransfer: { files, types: ['Files'] } })
    await until(() => ws.page('p5')!.content!.filter((b) => 'fileId' in b && b.fileId).length === 4)
    const made = ws.page('p5')!.content!.slice(before)
    expect(made.map((b) => b.type)).toEqual(['image', 'video', 'file', 'file'])
  })

  it('arrastar para a página sem sessão avisa e não cria nada; arrastar um bloco da página não é arquivo', async () => {
    open('p5')
    const before = ws.page('p5')!.content!.length
    const article = document.querySelector('article')!
    await fireEvent.drop(article, { dataTransfer: { files: [doc('a.txt')], types: ['Files'] } })
    expect(toast.message).toMatch(/Entre em um servidor/)
    await fireEvent.drop(article, { dataTransfer: { files: [], types: ['text/plain'] } })
    expect(ws.page('p5')!.content!.length).toBe(before)
  })

  it('soltar arquivos demais de uma vez cria no máximo dez blocos', async () => {
    signIn()
    open('p5')
    const before = ws.page('p5')!.content!.length
    const article = document.querySelector('article')!
    await fireEvent.drop(article, { dataTransfer: { files: Array.from({ length: 30 }, (_, i) => doc(`f${i}.bin`, 10)), types: ['Files'] } })
    expect(ws.page('p5')!.content!.length).toBe(before + 10)
  })

  it('numa página só de leitura soltar arquivo não cria nada', async () => {
    signIn()
    open('s2')
    const before = ws.page('s2')!.content!.length
    await fireEvent.drop(document.querySelector('article')!, { dataTransfer: { files: [doc('a.txt')], types: ['Files'] } })
    expect(ws.page('s2')!.content!.length).toBe(before)
    expect(server.seen).toHaveLength(0)
  })

  it('apagar o bloco de um arquivo avisa o servidor; apagar a página de vez apaga os arquivos dela', async () => {
    signIn()
    setBlocks([{ id: 'f', type: 'file', fileId: 'f1', name: 'a.bin', size: 5, mime: '', level: 3 }])
    server.files.set('f1', { id: 'f1', size: 5, mime: '', level: 3, name: 'a.bin', encrypted: false, createdAt: Date.now(), bytes: null })
    open('p5')
    await click(screen.getByRole('button', { name: /Opções de Arquivo 1/ }))
    await click(screen.getByRole('menuitem', { name: 'Excluir' }))
    await until(() => server.orphaned.has('f1'))
    cleanup()
    // a page deleted for good takes its files along
    setBlocks([{ id: 'g', type: 'file', fileId: 'f2', name: 'b.bin', size: 5, mime: '', level: 3 }], 'p0')
    server.files.set('f2', { id: 'f2', size: 5, mime: '', level: 3, name: 'b.bin', encrypted: false, createdAt: Date.now(), bytes: null })
    ws.deleteForever('p0')
    await until(() => server.deleted.has('f2'))
  })

  it('axe: a página com um arquivo, um selo de envio em andamento e o seletor vazio', async () => {
    signIn()
    server.delay = 40
    setBlocks([
      { id: 'a', type: 'file', fileId: 'f1', name: 'a.bin', size: 5, mime: '', level: 3 },
      { id: 'b', type: 'file', fileId: '', name: '', size: 0, mime: '', level: 3 },
      { id: 'c', type: 'image', name: null, src: null },
    ])
    server.files.set('f1', { id: 'f1', size: 5, mime: '', level: 3, name: 'a.bin', encrypted: false, createdAt: Date.now(), bytes: null })
    open('p5')
    expect(await violations()).toEqual([])
    await fireEvent.change(screen.getAllByLabelText('Arraste um arquivo aqui ou clique para escolher')[0], { target: { files: [doc('x.bin', 2_000_000)] } })
    await screen.findByRole('progressbar')
    expect(await violations()).toEqual([])
  })
})

