import { render } from '@testing-library/svelte'
import { describe, expect, it } from 'vitest'
import StatusDot from './StatusDot.svelte'

describe('StatusDot', () => {
  it('tem o tamanho de uma letra (80% do corpo, arredondado)', () => {
    const { getByTestId } = render(StatusDot, { tone: 'online', fontSize: 11, testid: 'd' })
    expect(getByTestId('d').style.width).toBe('9px')
    const { getByTestId: second } = render(StatusDot, { tone: 'online', fontSize: 12, testid: 'e' })
    expect(second('e').style.height).toBe('10px')
  })

  it('verde online, vermelha offline, e o anel só pulsa sem "reduzir movimento"', () => {
    const on = render(StatusDot, { tone: 'online', fontSize: 11, testid: 'on' }).getByTestId('on')
    expect(on.querySelector('.bg-accent-line')).toBeTruthy()
    const off = render(StatusDot, { tone: 'offline', fontSize: 11, testid: 'off' }).getByTestId('off')
    expect(off.querySelector('.bg-offline')).toBeTruthy()
    expect(off.querySelector('.bg-accent-line')).toBeNull()
    expect(off.firstElementChild?.className).toContain('motion-safe:animate-pulse-ring')
  })
})
