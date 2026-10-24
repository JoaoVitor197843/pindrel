import { describe, expect, it } from 'vitest'

const sources = import.meta.glob<string>('/src/**/*.svelte', { query: '?raw', import: 'default', eager: true })

// `h-[13.5]` generates no CSS (the unit is missing) and the button collapses; the right form is `h-13.5` or `h-[54px]`.
// only the sizing utilities: leading, opacity, z, flex etc. accept a bare number.
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
