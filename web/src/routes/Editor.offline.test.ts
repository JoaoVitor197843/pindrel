import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { resetNearView } from '../lib/components/editor/nearView'
import { sampleWorkspace } from '../lib/sample'
import { toast } from '../lib/stores/toast.svelte'
import type { Workspace } from '../lib/stores/workspace.svelte'
import { viewport } from '../test/setup'
import Editor from './Editor.svelte'

// The editor's chunk cannot be fetched (the server is down and it was never cached)
vi.mock('../lib/components/editor/rich/engine', async (orig) => ({
  ...(await orig<typeof import('../lib/components/editor/rich/engine')>()),
  loadEngine: () => Promise.reject(new Error('Failed to fetch dynamically imported module')),
}))

let ws: Workspace
beforeEach(() => {
  viewport.set(1400)
  toast.message = ''
  ws = sampleWorkspace()
})
afterEach(() => {
  cleanup()
  resetNearView()
})

const open = () => render(Editor, { ws, id: 'p0', onback: vi.fn() })
const blockAt = (n: number) => ws.page('p0')!.content![n] as { text: string }
async function focusPlain(label = 'Parágrafo') {
  screen.getByRole('textbox', { name: label }).focus()
  await waitFor(() => expect(document.querySelector('textarea[data-plain]')).not.toBeNull())
  return document.querySelector<HTMLTextAreaElement>('textarea[data-plain]')!
}

describe('Editor sem conexão: o editor completo não carrega e o texto continua editável', () => {
  it('focar um parágrafo abre um campo de texto simples com o texto do bloco, e avisa', async () => {
    open()
    const original = blockAt(1).text
    const area = await focusPlain()
    expect(area.value).toBe(original)
    await waitFor(() => expect(toast.message).toMatch(/Sem conexão/))
  })

  it('digitar grava no bloco, com os marcadores à vista', async () => {
    open()
    const area = await focusPlain()
    await fireEvent.input(area, { target: { value: 'Texto com **negrito** escrito sem rede' } })
    expect(blockAt(1).text).toBe('Texto com **negrito** escrito sem rede')
  })

  it('Enter no meio divide o bloco em dois', async () => {
    open()
    const area = await focusPlain()
    await fireEvent.input(area, { target: { value: 'primeira segunda' } })
    area.setSelectionRange(8, 8)
    const before = ws.page('p0')!.content!.length
    await fireEvent.keyDown(area, { key: 'Enter' })
    const blocks = ws.page('p0')!.content!
    expect(blocks.length).toBe(before + 1)
    expect((blocks[1] as { text: string }).text).toBe('primeira')
    expect((blocks[2] as { text: string }).text).toBe(' segunda')
  })

  it('Backspace num parágrafo vazio apaga o bloco', async () => {
    open()
    const area = await focusPlain()
    await fireEvent.input(area, { target: { value: '' } })
    const before = ws.page('p0')!.content!.length
    await fireEvent.keyDown(area, { key: 'Backspace' })
    expect(ws.page('p0')!.content!.length).toBe(before - 1)
  })

  it('um texto enorme é cortado no limite do bloco, como no editor completo', async () => {
    open()
    const area = await focusPlain()
    expect(area.maxLength).toBe(20_000)
  })

  it('o aviso aparece uma vez só, não a cada bloco focado', async () => {
    open()
    // the first test of this file already had the warning shown
    await focusPlain()
    toast.message = ''
    ;(document.activeElement as HTMLElement).blur()
    await waitFor(() => expect(document.querySelector('textarea[data-plain]')).toBeNull())
    await focusPlain()
    expect(toast.message).toBe('')
  })

  it('o campo de texto simples respeita a página só de leitura (lixeira): nada abre', async () => {
    ws.trash('p0')
    open()
    screen.getByRole('textbox', { name: 'Parágrafo' }).focus()
    await new Promise((r) => setTimeout(r, 50))
    expect(document.querySelector('textarea[data-plain]')).toBeNull()
  })
})
