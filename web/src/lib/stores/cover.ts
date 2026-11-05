// A page cover is a gradient built from the app's own colours: a short text spec is stored, never CSS, so what is saved
// (and what an import could carry) is always something this file knows how to draw.
import { COVERS } from './blocks'

export interface PaletteColor {
  id: string
  label: string
  hex: string
}

export const PALETTE: readonly PaletteColor[] = [
  { id: 'verde', label: 'Verde', hex: '#6b8e61' },
  { id: 'lima', label: 'Lima', hex: '#a8c45a' },
  { id: 'turquesa', label: 'Turquesa', hex: '#6bb3a8' },
  { id: 'ceu', label: 'Céu', hex: '#6fb8e0' },
  { id: 'azul', label: 'Azul', hex: '#8aa8c4' },
  { id: 'violeta', label: 'Violeta', hex: '#9a86d4' },
  { id: 'ameixa', label: 'Ameixa', hex: '#c196ad' },
  { id: 'rosa', label: 'Rosa', hex: '#d9788f' },
  { id: 'ferrugem', label: 'Ferrugem', hex: '#d98a6c' },
  { id: 'ouro', label: 'Ouro', hex: '#d1ad5a' },
  { id: 'areia', label: 'Areia', hex: '#cdbd9a' },
  { id: 'ardosia', label: 'Ardósia', hex: '#7a8794' },
  { id: 'grafite', label: 'Grafite', hex: '#4a4a44' },
]

/** Multi-colour gradients, in order from the start to the end. */
export const MIXES: readonly { key: string; label: string; stops: string[] }[] = [
  { key: 'arco-iris', label: 'Arco-íris', stops: ['rosa', 'ferrugem', 'ouro', 'lima', 'turquesa', 'ceu', 'violeta'] },
  { key: 'por-do-sol', label: 'Pôr do sol', stops: ['violeta', 'rosa', 'ferrugem', 'ouro'] },
  { key: 'aurora', label: 'Aurora', stops: ['verde', 'turquesa', 'ceu', 'violeta'] },
  { key: 'mar', label: 'Mar', stops: ['azul', 'ceu', 'turquesa'] },
  { key: 'floresta', label: 'Floresta', stops: ['grafite', 'verde', 'lima'] },
  { key: 'brasa', label: 'Brasa', stops: ['grafite', 'ferrugem', 'ouro'] },
  { key: 'algodao-doce', label: 'Algodão-doce', stops: ['ceu', 'ameixa', 'rosa'] },
  { key: 'deserto', label: 'Deserto', stops: ['areia', 'ouro', 'ferrugem'] },
]

export const DIRECTIONS = [
  { key: 'r', label: 'Para a direita', glyph: '→', css: '90deg' },
  { key: 'dr', label: 'Na diagonal', glyph: '↘', css: '120deg' },
  { key: 'd', label: 'Para baixo', glyph: '↓', css: '180deg' },
  { key: 'dl', label: 'Na outra diagonal', glyph: '↙', css: '240deg' },
] as const

export type Direction = (typeof DIRECTIONS)[number]['key']

const color = (id: string) => PALETTE.find((c) => c.id === id)
const dirCss = (key: string | undefined) => DIRECTIONS.find((d) => d.key === key)?.css ?? '120deg'
// the colours sit on a dark page: a part of the page's own background keeps them from shouting
const tone = (hex: string, pct = 78) => `color-mix(in oklab, ${hex} ${pct}%, var(--color-bg))`

export const soloSpec = (id: string) => `solid:${id}`
export const monoSpec = (id: string) => `mono:${id}`
export const duoSpec = (a: string, b: string, dir: Direction = 'dr') => `duo:${a}:${b}:${dir}`
export const mixSpec = (key: string) => `mix:${key}`

/** The CSS for a cover spec, or null when it is not one (an unknown colour, a made-up kind, anything else). */
export function coverCss(spec: string): string | null {
  const legacy = COVERS.find((c) => c.key === spec)
  if (legacy) return legacy.css
  if (typeof spec !== 'string' || spec.length > 60) return null
  const [kind, a, b, c] = spec.split(':')
  switch (kind) {
    case 'solid': {
      const col = color(a)
      return col && b === undefined ? tone(col.hex) : null
    }
    case 'mono': {
      const col = color(a)
      return col && b === undefined ? `linear-gradient(120deg, ${tone(col.hex, 88)}, ${tone(col.hex, 32)})` : null
    }
    case 'duo': {
      const from = color(a)
      const to = color(b)
      if (!from || !to || c === undefined || !DIRECTIONS.some((d) => d.key === c)) return null
      return `linear-gradient(${dirCss(c)}, ${tone(from.hex)}, ${tone(to.hex)})`
    }
    case 'mix': {
      const mix = MIXES.find((m) => m.key === a)
      return mix && b === undefined ? `linear-gradient(120deg, ${mix.stops.map((id) => tone(color(id)!.hex)).join(', ')})` : null
    }
    default:
      return null
  }
}

/** '' (no cover) or something `coverCss` can draw. */
export const isCover = (spec: string) => spec === '' || coverCss(spec) !== null

/** What a spec is made of, so the picker can show the current choice: [kind, ...parts]. */
export function describeCover(spec: string): { kind: 'preset' | 'solid' | 'mono' | 'duo' | 'mix' | 'none'; a?: string; b?: string; dir?: Direction } {
  if (!spec || coverCss(spec) === null) return { kind: 'none' }
  if (COVERS.some((c) => c.key === spec)) return { kind: 'preset', a: spec }
  const [kind, a, b, c] = spec.split(':')
  if (kind === 'duo') return { kind, a, b, dir: c as Direction }
  return { kind: kind as 'solid' | 'mono' | 'mix', a }
}
