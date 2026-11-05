import { describe, expect, it } from 'vitest'
import { COVERS } from './blocks'
import { DIRECTIONS, MIXES, PALETTE, coverCss, describeCover, duoSpec, isCover, mixSpec, monoSpec, soloSpec } from './cover'

describe('coverCss', () => {
  it('desenha cada tipo de especificação', () => {
    expect(coverCss(soloSpec('verde'))).toMatch(/^color-mix\(in oklab, #6b8e61 78%, var\(--color-bg\)\)$/)
    expect(coverCss(monoSpec('rosa'))).toMatch(/^linear-gradient\(120deg, .*#d9788f 88%.*#d9788f 32%/)
    expect(coverCss(duoSpec('verde', 'azul', 'r'))).toMatch(/^linear-gradient\(90deg, .*#6b8e61.*#8aa8c4/)
    expect(coverCss(mixSpec('arco-iris'))!.match(/color-mix/g)).toHaveLength(7)
  })

  it('toda cor, combinação, direção e capa clássica tem CSS', () => {
    for (const c of PALETTE) {
      expect(coverCss(soloSpec(c.id))).toBeTruthy()
      expect(coverCss(monoSpec(c.id))).toBeTruthy()
      for (const o of PALETTE) for (const d of DIRECTIONS) expect(coverCss(duoSpec(c.id, o.id, d.key))).toBeTruthy()
    }
    for (const m of MIXES) {
      expect(m.stops.length).toBeGreaterThanOrEqual(3)
      expect(coverCss(mixSpec(m.key)), m.key).toBeTruthy()
    }
    for (const c of COVERS) expect(coverCss(c.key)).toBe(c.css)
  })

  it('recusa o que não é especificação: cor ou direção desconhecida, partes a mais, a menos ou CSS solto', () => {
    const bad = [
      '', 'solid', 'solid:', 'solid:nao', 'solid:verde:extra', 'mono:nao', 'duo:verde', 'duo:verde:azul', 'duo:verde:azul:zz', 'duo:x:azul:r', 'mix:', 'mix:nao', 'mix:arco-iris:x',
      'url(http://evil)', 'red', '#fff', 'linear-gradient(red, blue)', 'solid:verde;color:red', 'solid:verde)', 'SOLID:verde', ' solid:verde', 'x'.repeat(200), '__proto__', 'constructor',
    ]
    for (const spec of bad) expect(coverCss(spec), spec).toBeNull()
  })

  it('nada que não seja texto desenha', () => {
    for (const v of [null, undefined, 1, {}, []] as unknown[]) expect(coverCss(v as string)).toBeNull()
  })

  it('isCover aceita vazio (sem capa) e o que desenha', () => {
    expect(isCover('')).toBe(true)
    expect(isCover('mix:aurora')).toBe(true)
    expect(isCover('oceano')).toBe(true)
    expect(isCover('nao')).toBe(false)
  })

  it('describeCover diz do que a capa é feita', () => {
    expect(describeCover('')).toEqual({ kind: 'none' })
    expect(describeCover('lixo')).toEqual({ kind: 'none' })
    expect(describeCover('musgo')).toEqual({ kind: 'preset', a: 'musgo' })
    expect(describeCover('solid:ouro')).toEqual({ kind: 'solid', a: 'ouro' })
    expect(describeCover('duo:rosa:azul:d')).toEqual({ kind: 'duo', a: 'rosa', b: 'azul', dir: 'd' })
    expect(describeCover('mix:mar')).toEqual({ kind: 'mix', a: 'mar' })
  })

  it('as cores têm ids únicos e hex válido', () => {
    expect(new Set(PALETTE.map((c) => c.id)).size).toBe(PALETTE.length)
    for (const c of PALETTE) expect(c.hex).toMatch(/^#[0-9a-f]{6}$/)
  })
})
