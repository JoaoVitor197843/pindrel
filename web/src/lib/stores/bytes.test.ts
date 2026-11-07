import { describe, expect, it } from 'vitest'
import { formatBytes } from './bytes'

describe('formatBytes', () => {
  it('escolhe a unidade e arredonda', () => {
    expect(formatBytes(0)).toBe('0 B')
    expect(formatBytes(999)).toBe('999 B')
    expect(formatBytes(1000)).toBe('1.0 KB')
    expect(formatBytes(1_500)).toBe('1.5 KB')
    expect(formatBytes(312_000)).toBe('312 KB')
    expect(formatBytes(1_400_000)).toBe('1.4 MB')
    expect(formatBytes(2_000_000_000)).toBe('2.0 GB')
    expect(formatBytes(5e12)).toBe('5.0 TB')
    expect(formatBytes(5e15)).toBe('5000 TB')
  })

  it('valores estranhos não quebram', () => {
    for (const v of [-1, NaN, Infinity, -Infinity, 1e300]) expect(() => formatBytes(v)).not.toThrow()
    expect(formatBytes(-5)).toBe('0 B')
    expect(formatBytes(NaN)).toBe('0 B')
  })
})
