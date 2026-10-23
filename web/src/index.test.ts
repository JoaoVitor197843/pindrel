import { describe, expect, it } from 'vitest'
import html from '../index.html?raw'

const doc = new DOMParser().parseFromString(html, 'text/html')

describe('index.html', () => {
  it('traz o esqueleto do login dentro do #app, escondido dos leitores de tela', () => {
    const skeleton = doc.querySelector('#app #skeleton')
    expect(skeleton?.getAttribute('aria-hidden')).toBe('true')
    expect(skeleton?.querySelector('.sk-head')).toBeTruthy()
    expect(skeleton?.querySelector('.sk-side')).toBeTruthy()
    expect(skeleton?.querySelector('.sk-form')).toBeTruthy()
  })

  it('não depende de JavaScript nem de arquivos externos, só do módulo do app', () => {
    expect(doc.querySelectorAll('script:not([type=module])')).toHaveLength(0)
    expect(doc.querySelectorAll('link[rel=stylesheet]')).toHaveLength(0)
  })

  it('usa o mesmo ponto de quebra do Login e respeita "reduzir movimento"', () => {
    expect(html).toContain('min-width: 840px')
    expect(html).toContain('prefers-reduced-motion: reduce')
  })

  it('pinta o fundo do tema desde o início (sem flash branco)', () => {
    expect(html).toMatch(/html, body \{[^}]*background: #141412/)
  })
})
