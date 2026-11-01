import { describe, expect, it } from 'vitest'
import { currentTheme } from './season'

describe('tema forçado (debug)', () => {
  it('?logo= força um tema; valor desconhecido é ignorado', () => {
    const day = new Date(2026, 7, 15)
    expect(currentTheme(day, '?logo=halloween')).toBe('halloween')
    expect(currentTheme(day, '?logo=nada')).toBe('normal')
    expect(currentTheme(new Date(2026, 11, 25), '')).toBe('d25')
  })
})
