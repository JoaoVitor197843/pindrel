import { fireEvent, render, screen } from '@testing-library/svelte'
import { afterEach, describe, expect, it, vi } from 'vitest'
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

  describe('teclado virtual', () => {
    function fakeViewport(height: number, offsetTop = 0) {
      const target = new EventTarget() as EventTarget & { height: number; offsetTop: number }
      target.height = height
      target.offsetTop = offsetTop
      setViewport(target)
      return target
    }
    // does not use vi.unstubAllGlobals: it also undoes the setup's fake fetch
    const setViewport = (value: unknown) => Object.defineProperty(window, 'visualViewport', { value, configurable: true })
    afterEach(() => setViewport(undefined))
    const gap = () => screen.getByTestId('recovery-overlay').style.paddingBottom

    it('sem visualViewport não há folga e nada quebra', () => {
      setViewport(null)
      render(RecoveryKeyModal, { onclose: vi.fn() })
      expect(gap()).toBe('0px')
    })

    it('a folga embaixo acompanha a altura do teclado e some ao fechá-lo', async () => {
      const viewport = fakeViewport(window.innerHeight)
      render(RecoveryKeyModal, { onclose: vi.fn() })
      expect(gap()).toBe('0px')

      viewport.height = window.innerHeight - 300
      viewport.dispatchEvent(new Event('resize'))
      await vi.waitFor(() => expect(gap()).toBe('300px'))

      viewport.height = window.innerHeight
      viewport.dispatchEvent(new Event('resize'))
      await vi.waitFor(() => expect(gap()).toBe('0px'))
    })

    it('a página rolada pelo navegador (offsetTop) não conta como teclado', async () => {
      const viewport = fakeViewport(window.innerHeight - 300, 300)
      render(RecoveryKeyModal, { onclose: vi.fn() })
      expect(gap()).toBe('0px')
      viewport.offsetTop = 100
      viewport.dispatchEvent(new Event('scroll'))
      await vi.waitFor(() => expect(gap()).toBe('200px'))
    })

    it('valores absurdos (viewport maior que a janela) não dão folga negativa', () => {
      fakeViewport(window.innerHeight + 5000)
      render(RecoveryKeyModal, { onclose: vi.fn() })
      expect(gap()).toBe('0px')
    })

    it('desmontar solta os ouvintes', () => {
      const viewport = fakeViewport(window.innerHeight)
      const remove = vi.spyOn(viewport, 'removeEventListener')
      const { unmount } = render(RecoveryKeyModal, { onclose: vi.fn() })
      unmount()
      expect(remove).toHaveBeenCalledWith('resize', expect.any(Function))
      expect(remove).toHaveBeenCalledWith('scroll', expect.any(Function))
    })
  })
})
