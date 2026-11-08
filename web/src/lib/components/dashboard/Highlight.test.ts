import { render } from '@testing-library/svelte'
import { describe, expect, it } from 'vitest'
import Highlight from './Highlight.svelte'

const marks = (text: string, query: string) => {
  const { container } = render(Highlight, { text, query })
  return { marks: [...container.querySelectorAll('mark')].map((m) => m.textContent), all: container.textContent }
}

describe('Highlight', () => {
  it('marca todas as ocorrências ignorando acento e caixa, sem alterar o texto', () => {
    const r = marks('Pão de pao, PÃO', 'pao')
    expect(r.marks).toEqual(['Pão', 'pao', 'PÃO'])
    expect(r.all).toBe('Pão de pao, PÃO')
  })

  it('sem busca, espaços ou sem ocorrência não marca nada', () => {
    expect(marks('texto', '').marks).toEqual([])
    expect(marks('texto', '   ').marks).toEqual([])
    expect(marks('texto', 'zzz').marks).toEqual([])
  })

  it('texto com HTML aparece como texto, nunca vira elemento', () => {
    const { container } = render(Highlight, { text: '<img src=x onerror=alert(1)> a', query: 'a' })
    expect(container.querySelector('img')).toBeNull()
    expect(container.textContent).toContain('<img src=x')
  })

  it('acento decomposto não desloca as marcas (mostra o texto como está)', () => {
    const r = marks('café cafe', 'cafe')
    expect(r.all).toBe('café cafe')
  })

  it('termo gigante ou com caracteres de regex não quebra', () => {
    expect(marks('a.b (c) [d]', '.*').marks).toEqual([])
    expect(marks('abc', 'x'.repeat(10_000)).marks).toEqual([])
    expect(marks('a(b', '(').marks).toEqual(['('])
  })
})
