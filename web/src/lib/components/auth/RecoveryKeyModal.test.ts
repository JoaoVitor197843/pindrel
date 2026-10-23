import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'
import RecoveryKeyModal from './RecoveryKeyModal.svelte'

describe('RecoveryKeyModal', () => {
  it('é um diálogo modal com título e campo nomeados', () => {
    render(RecoveryKeyModal, { onclose: vi.fn() })
    const dialog = screen.getByRole('dialog')
    expect(dialog.getAttribute('aria-modal')).toBe('true')
    expect(screen.getByRole('heading', { name: 'Chave de recuperação' })).toBeTruthy()
    expect(screen.getByLabelText('Código de recuperação')).toBeTruthy()
  })

  it('fecha por Escape, pelo fundo e pelo botão; outras teclas não fecham', async () => {
    const onclose = vi.fn()
    render(RecoveryKeyModal, { onclose })

    await fireEvent.keyDown(window, { key: 'a' })
    await fireEvent.keyDown(window, { key: 'Enter' })
    expect(onclose).not.toHaveBeenCalled()

    await fireEvent.keyDown(window, { key: 'Escape' })
    await fireEvent.click(screen.getByRole('button', { name: 'Fechar' }))
    await fireEvent.click(screen.getByRole('button', { name: 'Recuperar acesso' }))
    expect(onclose).toHaveBeenCalledTimes(3)
  })

  it('clicar dentro do diálogo não o fecha', async () => {
    const onclose = vi.fn()
    render(RecoveryKeyModal, { onclose })
    await fireEvent.click(screen.getByRole('dialog'))
    await fireEvent.click(screen.getByLabelText('Código de recuperação'))
    expect(onclose).not.toHaveBeenCalled()
  })

  it('aceita código gigante ou estranho no campo', async () => {
    render(RecoveryKeyModal, { onclose: vi.fn() })
    const input = screen.getByLabelText('Código de recuperação') as HTMLInputElement
    for (const v of ['', '  ', 'x'.repeat(50_000), '😀-😀-😀']) {
      await fireEvent.input(input, { target: { value: v } })
      expect(input.value).toBe(v)
    }
  })
})
