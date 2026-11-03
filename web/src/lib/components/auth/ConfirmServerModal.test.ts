import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'
import ConfirmServerModal from './ConfirmServerModal.svelte'

const props = () => ({ name: 'Casa', onconfirm: vi.fn(), oncancel: vi.fn() })

describe('ConfirmServerModal', () => {
  it('é um diálogo modal que nomeia o servidor e avisa do risco', () => {
    render(ConfirmServerModal, props())
    expect(screen.getByRole('alertdialog').getAttribute('aria-modal')).toBe('true')
    expect(screen.getByRole('heading', { name: 'Este servidor mudou' })).toBeTruthy()
    expect(screen.getByText(/“Casa”/)).toBeTruthy()
    expect(screen.getByText(/senha/)).toBeTruthy()
  })

  it('o foco começa no botão seguro: Enter por reflexo cancela', () => {
    render(ConfirmServerModal, props())
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Cancelar' }))
  })

  it('Continuar mesmo assim só confirma pelo botão', async () => {
    const p = props()
    render(ConfirmServerModal, p)
    await fireEvent.click(screen.getByRole('button', { name: 'Continuar mesmo assim' }))
    expect(p.onconfirm).toHaveBeenCalledOnce()
    expect(p.oncancel).not.toHaveBeenCalled()
  })

  it('Cancelar, Escape e o fundo cancelam; outras teclas e cliques dentro não', async () => {
    const p = props()
    render(ConfirmServerModal, p)
    await fireEvent.keyDown(window, { key: 'Enter' })
    await fireEvent.keyDown(window, { key: ' ' })
    await fireEvent.click(screen.getByRole('alertdialog'))
    expect(p.oncancel).not.toHaveBeenCalled()

    await fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    await fireEvent.keyDown(window, { key: 'Escape' })
    await fireEvent.click(screen.getByTestId('backdrop'))
    expect(p.oncancel).toHaveBeenCalledTimes(3)
    expect(p.onconfirm).not.toHaveBeenCalled()
  })

  it('nome gigante ou com tags aparece como texto, sem quebrar nem virar HTML', () => {
    render(ConfirmServerModal, { ...props(), name: `<img src=x onerror=alert(1)>${'N'.repeat(5000)}` })
    expect(document.querySelector('img')).toBeNull()
    expect(screen.getByRole('alertdialog').textContent).toContain('<img src=x onerror=alert(1)>')
  })
})
