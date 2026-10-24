import { describe, expect, it } from 'vitest'
import { currentTheme, easter, seasonalTheme, type LogoTheme, type RegionalRule } from './season'

const d = (y: number, m: number, day: number) => new Date(y, m - 1, day)
const iso = (x: Date) => `${x.getFullYear()}-${x.getMonth() + 1}-${x.getDate()}`

describe('easter', () => {
  it('bate com as datas conhecidas', () => {
    expect(iso(easter(2025))).toBe('2025-4-20')
    expect(iso(easter(2026))).toBe('2026-4-5')
    expect(iso(easter(2027))).toBe('2027-3-28')
    expect(iso(easter(2024))).toBe('2024-3-31')
    expect(iso(easter(2038))).toBe('2038-4-25')
  })
})

describe('seasonalTheme', () => {
  const cases: [string, Date, LogoTheme][] = [
    ['halloween', d(2026, 10, 31), 'halloween'],
    ['24/12', d(2026, 12, 24), 'd24'],
    ['25/12', d(2026, 12, 25), 'd25'],
    ['31/12', d(2026, 12, 31), 'd31'],
    ['01/01', d(2026, 1, 1), 'd1'],
    ['namorados', d(2026, 6, 12), 'namorados'],
    ['junino', d(2026, 6, 24), 'junino'],
  ]
  for (const [name, date, theme] of cases) {
    it(`${name}: o dia, o anterior e o seguinte`, () => {
      expect(seasonalTheme(date)).toBe(theme)
      expect(seasonalTheme(new Date(date.getFullYear(), date.getMonth(), date.getDate() - 1))).not.toBe(theme)
      expect(seasonalTheme(new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1))).not.toBe(theme)
    })
  }

  it('um dia comum é normal', () => {
    expect(seasonalTheme(d(2026, 8, 15))).toBe('normal')
    expect(seasonalTheme(d(2026, 3, 3))).toBe('normal')
  })

  it('dia do programador: 13/09, ou 12/09 em ano bissexto', () => {
    expect(seasonalTheme(d(2026, 9, 13))).toBe('dev')
    expect(seasonalTheme(d(2026, 9, 12))).toBe('normal')
    expect(seasonalTheme(d(2026, 9, 14))).toBe('normal')
    expect(seasonalTheme(d(2028, 9, 12))).toBe('dev')
    expect(seasonalTheme(d(2028, 9, 13))).toBe('normal')
    expect(seasonalTheme(d(2028, 9, 11))).toBe('normal')
  })

  for (const year of [2025, 2026, 2027]) {
    it(`páscoa e carnaval de ${year}`, () => {
      const e = easter(year)
      const at = (n: number) => new Date(year, e.getMonth(), e.getDate() + n)
      expect([-3, -2, -1, 0, 1].map((n) => seasonalTheme(at(n)))).toEqual([
        'normal',
        'pascoa',
        'pascoa',
        'pascoa',
        'normal',
      ])
      expect([-51, -50, -49, -48, -47, -46].map((n) => seasonalTheme(at(n)))).toEqual([
        'normal',
        'carnaval',
        'carnaval',
        'carnaval',
        'carnaval',
        'normal',
      ])
    })
  }

  it('Carnaval de 2025: sábado 1/3 a terça 4/3', () => {
    expect([28, 1, 2, 3, 4, 5].map((n, i) => seasonalTheme(i === 0 ? d(2025, 2, n) : d(2025, 3, n)))).toEqual([
      'normal',
      'carnaval',
      'carnaval',
      'carnaval',
      'carnaval',
      'normal',
    ])
  })

  it('usa a data local, não a UTC', () => {
    // 31/12 at 23:30 local is already 1/1 in UTC for anyone west of Greenwich.
    expect(seasonalTheme(new Date(2026, 11, 31, 23, 30))).toBe('d31')
    expect(seasonalTheme(new Date(2027, 0, 1, 0, 30))).toBe('d1')
  })
})

describe('regiões', () => {
  const rules: Record<string, RegionalRule[]> = {
    BR: [(x) => (x.getMonth() === 7 && x.getDate() === 15 ? 'd1' : null)],
  }

  it('sem regra para a região, vale a tabela global', () => {
    expect(seasonalTheme(d(2026, 8, 15), 'PT', rules)).toBe('normal')
    expect(seasonalTheme(d(2026, 8, 15), null, rules)).toBe('normal')
    expect(seasonalTheme(d(2026, 8, 15))).toBe('normal')
  })

  it('a regra da região vale, sem diferenciar maiúsculas, e perde para nada quando devolve null', () => {
    expect(seasonalTheme(d(2026, 8, 15), 'br', rules)).toBe('d1')
    expect(seasonalTheme(d(2026, 8, 16), 'BR', rules)).toBe('normal')
  })

  it('a data regional vence a global no mesmo dia', () => {
    const clash: Record<string, RegionalRule[]> = { BR: [() => 'dev'] }
    expect(seasonalTheme(d(2026, 12, 25), 'BR', clash)).toBe('dev')
  })
})
