import 'fake-indexeddb/auto'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { beforeEach, describe, expect, it } from 'vitest'
import App from './App.svelte'
import { viewport } from './test/setup'

// The page as a person lives it: write something offline, close the tab, come back.
describe('App — notas guardadas no navegador', () => {
  beforeEach(() => viewport.set(1400))

  it('uma página criada e escrita continua lá depois de recarregar, no painel e pelo endereço dela', async () => {
    history.replaceState(null, '', '/?tela=painel&modo=local')
    render(App)
    await fireEvent.click(await screen.findByRole('button', { name: 'Criar primeira página' }))
    await fireEvent.click(screen.getAllByTestId('page-card')[0].querySelector('button')!)
    const title = await screen.findByRole('textbox', { name: /título/i })
    await fireEvent.input(title, { target: { value: 'Receita de domingo' } })
    const id = location.pathname.split('/').pop()!
    // leaving the tab saves at once, without waiting for the pause after typing
    window.dispatchEvent(new Event('pagehide'))
    await new Promise((r) => setTimeout(r, 50))
    cleanup()

    history.replaceState(null, '', '/?tela=painel&modo=local')
    render(App)
    expect(await screen.findByText('Receita de domingo')).toBeTruthy()
    cleanup()

    // reload on the page's own address: the editor waits for the body and does not show "not found"
    history.replaceState(null, '', `/notes/${id}?tela=painel&modo=local`)
    render(App)
    await waitFor(() => expect((screen.getByRole('textbox', { name: /título/i }) as HTMLTextAreaElement).value).toBe('Receita de domingo'))
    expect(screen.queryByRole('heading', { name: 'Página não encontrada' })).toBeNull()
  })

  it('escrever numa página que veio do disco não a fecha nem a recarrega (a tela não pisca)', async () => {
    history.replaceState(null, '', '/?tela=painel&modo=local')
    render(App)
    await fireEvent.click(await screen.findByRole('button', { name: /Criar primeira página|Nova página/ }))
    await fireEvent.click(screen.getAllByTestId('page-card')[0].querySelector('button')!)
    await fireEvent.input(await screen.findByRole('textbox', { name: /título/i }), { target: { value: 'Veio do disco' } })
    const id = location.pathname.split('/').pop()!
    window.dispatchEvent(new Event('pagehide'))
    await new Promise((r) => setTimeout(r, 50))
    cleanup()

    history.replaceState(null, '', `/notes/${id}?tela=painel&modo=local`)
    render(App)
    const title = await screen.findByRole('textbox', { name: /título/i })
    await new Promise((r) => setTimeout(r, 100))
    const removed: Node[] = []
    const watch = new MutationObserver((list) => list.forEach((m) => m.removedNodes.forEach((n) => removed.push(n))))
    watch.observe(document.body, { childList: true, subtree: true })
    for (const text of ['A', 'Ab', 'Abc']) {
      await fireEvent.input(title, { target: { value: text } })
      await new Promise((r) => setTimeout(r, 150))
    }
    await new Promise((r) => setTimeout(r, 900))
    watch.disconnect()
    expect(document.body.contains(title)).toBe(true)
    expect(removed.some((n) => n.contains(title))).toBe(false)
  })
})
