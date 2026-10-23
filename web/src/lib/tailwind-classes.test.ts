import { describe, expect, it } from 'vitest'

const sources = import.meta.glob<string>('/src/**/*.svelte', { query: '?raw', import: 'default', eager: true })

// `h-[13.5]` não gera CSS (falta a unidade) e o botão colapsa; o certo é `h-13.5` ou `h-[54px]`.
// só as utilitárias de tamanho: leading, opacity, z, flex etc. aceitam número puro.
const unitless = /(?<![\w-])-?(?:min-|max-)?(?:h|w|size|gap|p[xytblr]?|m[xytblr]?|top|left|right|bottom|inset)-\[-?\d+(?:\.\d+)?\](?!\w)/g

describe('classes do Tailwind', () => {
  it('há componentes para checar', () => {
    expect(Object.keys(sources).length).toBeGreaterThan(5)
  })

  it('nenhum valor arbitrário sem unidade (gera classe vazia)', () => {
    const found = Object.entries(sources).flatMap(([file, src]) =>
      [...src.matchAll(unitless)].map((m) => `${file}: ${m[0]}`),
    )
    expect(found).toEqual([])
  })
})
