/// <reference types="node" />
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

/** Reads the palette from `app.css` itself, so changing a token without checking its contrast fails here. */
// vitest runs from web/
const css = readFileSync('src/app.css', 'utf8')
const rgb = (name: string): [number, number, number] => {
  const m = new RegExp(`--color-${name}:\\s*#([0-9a-f]{6})`, 'i').exec(css)
  if (!m) throw new Error(`token ${name} not found`)
  return [0, 2, 4].map((i) => parseInt(m[1].slice(i, i + 2), 16)) as [number, number, number]
}
const lin = (v: number) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
const lum = ([r, g, b]: number[]) => 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
const ratio = (a: number[], b: number[]) => {
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}
/** `over` painted at [alpha] on top of [under], as Tailwind's `bg-x/45` does. */
const blend = (over: number[], under: number[], alpha: number) => over.map((c, i) => Math.round(alpha * c + (1 - alpha) * under[i]))

const bg = rgb('bg')
const surface = rgb('surface')

describe('contraste das cores (WCAG AA)', () => {
  it.each([
    ['texto principal no fundo', rgb('fg'), bg],
    ['texto principal na superfície', rgb('fg'), surface],
    ['texto secundário (e placeholder) no fundo', rgb('muted'), bg],
    ['texto secundário na superfície', rgb('muted'), surface],
    ['texto secundário no hover do menu', rgb('muted'), blend(rgb('line'), surface, 0.4)],
    ['texto secundário no toque do menu', rgb('muted'), blend(rgb('line'), surface, 0.7)],
    ['link/acento no fundo', rgb('accent-line'), bg],
    ['link/acento na superfície', rgb('accent-line'), surface],
    ['item selecionado do menu', rgb('accent-text'), blend(rgb('accent'), surface, 0.45)],
    ['erro (texto) na superfície', rgb('offline-text'), surface],
    ['erro (texto) no fundo', rgb('offline-text'), bg],
    ['servidor offline (nome) no destaque vermelho', rgb('muted'), blend(rgb('offline'), surface, 0.15)],
    ['tag rust no chip', rgb('tag-rust'), blend(rgb('tag-rust'), surface, 0.15)],
    ['tag azul no chip', rgb('tag-blue'), blend(rgb('tag-blue'), surface, 0.15)],
    ['tag teal no chip', rgb('tag-teal'), blend(rgb('tag-teal'), surface, 0.15)],
    ['tag dourada no chip', rgb('tag-gold'), blend(rgb('tag-gold'), surface, 0.15)],
    ['tag ameixa no chip', rgb('tag-plum'), blend(rgb('tag-plum'), surface, 0.15)],
    ['tag verde no chip', rgb('accent-text'), blend(rgb('accent-line'), surface, 0.15)],
    ['botão principal', rgb('on-cream'), rgb('cream')],
    ['letra do logo', rgb('fg'), rgb('accent')],
  ])('texto: %s tem pelo menos 4,5:1', (_, fg, back) => {
    expect(ratio(fg, back)).toBeGreaterThanOrEqual(4.5)
  })

  it.each([
    ['borda de campo no fundo', rgb('field-line'), bg],
    ['borda de campo na superfície', rgb('field-line'), surface],
    ['anel de foco no fundo', rgb('accent-line'), bg],
    ['anel de foco na superfície', rgb('accent-line'), surface],
    ['ponto offline na superfície', rgb('offline'), surface],
  ])('componente: %s tem pelo menos 3:1', (_, fg, back) => {
    expect(ratio(fg, back)).toBeGreaterThanOrEqual(3)
  })
})
