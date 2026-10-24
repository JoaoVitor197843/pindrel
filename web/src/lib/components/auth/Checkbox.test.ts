import { render, screen } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cubicBezier, easeIn, easeOut } from '../../animation'
import Checkbox from './Checkbox.svelte'

const box = () => screen.getByTestId('checkbox-box')
const t = () => Number(box().dataset.t)
const path = () => box().querySelector('path')!.getAttribute('d')
const body = () => box().querySelectorAll('rect')[0]

describe('curvas', () => {
  it('easeIn/easeOut batem com os valores do Flutter nas pontas e no meio', () => {
    expect(easeIn(0)).toBe(0)
    expect(easeIn(1)).toBe(1)
    expect(easeIn(0.5)).toBeCloseTo(0.3153, 3)
    expect(easeOut(0.5)).toBeCloseTo(0.6847, 3)
    expect(cubicBezier(0, 0, 1, 1)(0.3)).toBeCloseTo(0.3, 3)
  })
})

describe('Checkbox — sem animação (jsdom, "reduzir movimento")', () => {
  it('marcado: caixa cheia, preenchida e com o certo inteiro', () => {
    render(Checkbox, { checked: true })
    expect(t()).toBe(1)
    expect(body().getAttribute('fill-opacity')).toBe('1')
    expect(path()).toBe('M2.7 8.1L7.2 12.6L15.3 4.5')
  })

  it('desmarcado: sem preenchimento nem certo', () => {
    render(Checkbox, { checked: false })
    expect(t()).toBe(0)
    expect(body().getAttribute('fill-opacity')).toBe('0')
    expect(path()).toBe('')
  })

  it('mudar a propriedade vai direto ao fim', async () => {
    const { rerender } = render(Checkbox, { checked: false })
    await rerender({ checked: true })
    expect(t()).toBe(1)
    await rerender({ checked: false })
    expect(t()).toBe(0)
  })
})

describe('Checkbox — animado', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['requestAnimationFrame', 'cancelAnimationFrame', 'performance'] })
    ;(Element.prototype as { animate?: unknown }).animate = () => ({})
  })
  afterEach(() => {
    vi.useRealTimers()
    delete (Element.prototype as { animate?: unknown }).animate
  })

  it('marcar dura 200 ms: a caixa encolhe até a metade, depois o certo é traçado', async () => {
    const { rerender } = render(Checkbox, { checked: false })
    await rerender({ checked: true })

    await vi.advanceTimersByTimeAsync(100)
    const half = t()
    expect(half).toBeGreaterThan(0.1)
    expect(half).toBeLessThan(0.5)
    expect(path()).toBe('') // ainda na primeira metade: só encolhe e preenche
    expect(Number(body().getAttribute('width'))).toBeLessThan(18)

    await vi.advanceTimersByTimeAsync(70)
    expect(path()).not.toBe('') // a perna curta já aparece
    expect(t()).toBeLessThan(1)

    await vi.advanceTimersByTimeAsync(100)
    expect(t()).toBe(1)
    expect(path()).toBe('M2.7 8.1L7.2 12.6L15.3 4.5')
    expect(Number(body().getAttribute('width'))).toBe(18)
  })

  it('interrompido no meio, volta de onde estava (sem salto) e termina desmarcado', async () => {
    const { rerender } = render(Checkbox, { checked: false })
    await rerender({ checked: true })
    await vi.advanceTimersByTimeAsync(120)
    const before = t()
    await rerender({ checked: false })
    expect(Math.abs(t() - before)).toBeLessThan(0.2)
    await vi.advanceTimersByTimeAsync(300)
    expect(t()).toBe(0)
    expect(path()).toBe('')
  })

  it('cliques em rajada terminam no estado certo e sem quadros pendentes', async () => {
    const { rerender } = render(Checkbox, { checked: true })
    for (let i = 0; i < 25; i++) {
      await rerender({ checked: i % 2 === 1 })
      await vi.advanceTimersByTimeAsync(17)
    }
    await vi.advanceTimersByTimeAsync(500)
    expect(t()).toBe(0) // o último valor foi i=24 (par): desmarcado
  })

  it('desmontar no meio cancela o quadro agendado', async () => {
    const cancel = vi.spyOn(globalThis, 'cancelAnimationFrame')
    const { rerender, unmount } = render(Checkbox, { checked: false })
    await rerender({ checked: true })
    await vi.advanceTimersByTimeAsync(50)
    unmount()
    expect(cancel).toHaveBeenCalled()
  })
})
