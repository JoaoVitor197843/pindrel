import { describe, expect, it } from 'vitest'
import { ago, blockText, outline, pageStats, wordCount, checklistProgress, excerptOf, makeBlock, moveItem, newId, type Block } from './blocks'

describe('blocks', () => {
  it('moveItem usa o vão de soltar: antes do item, não o índice final', () => {
    const l = ['a', 'b', 'c', 'd']
    expect(moveItem(l, 0, 3)).toBe(true)
    expect(l).toEqual(['b', 'c', 'a', 'd'])
    expect(moveItem(l, 3, 0)).toBe(true)
    expect(l).toEqual(['d', 'b', 'c', 'a'])
    // dropping on its own gap, or right after itself, moves nothing
    expect(moveItem(l, 1, 1)).toBe(false)
    expect(moveItem(l, 1, 2)).toBe(false)
    expect(l).toEqual(['d', 'b', 'c', 'a'])
    expect(moveItem(l, 0, 4)).toBe(true)
    expect(l.at(-1)).toBe('d')
  })

  it('moveItem recusa índices fora da lista sem mexer em nada', () => {
    const l = [1, 2, 3]
    for (const [from, at] of [[-1, 0], [3, 0], [0, -1], [0, 4], [Number.NaN, 1]] as const) expect(moveItem(l, from, at)).toBe(false)
    expect(l).toEqual([1, 2, 3])
  })

  it('newId nunca repete, mesmo chamado em sequência', () => {
    expect(new Set(Array.from({ length: 1000 }, () => newId())).size).toBe(1000)
  })

  it('makeBlock cria cada tipo com o formato certo', () => {
    expect(makeBlock('paragraph')).toMatchObject({ type: 'paragraph', text: '' })
    expect(makeBlock('code')).toMatchObject({ type: 'code', lang: 'texto' })
    const list = makeBlock('checklist')
    expect(list.type === 'checklist' && list.items).toHaveLength(1)
    const t = makeBlock('table')
    if (t.type !== 'table') throw new Error('table')
    expect(t.cols).toHaveLength(3)
    expect(t.rows).toHaveLength(3)
    expect(Object.keys(t.rows[0]).sort()).toEqual(t.cols.map((c) => c.id).sort())
    expect(makeBlock('image')).toMatchObject({ type: 'image', src: null })
  })

  it('o resumo do cartão ignora spoiler e bloco seguro', () => {
    const blocks: Block[] = [
      { id: '1', type: 'spoiler', text: 'segredo do spoiler' },
      { id: '2', type: 'secure', text: 'SENHA-123' },
      { id: '3', type: 'paragraph', text: '   ' },
      { id: '4', type: 'checklist', items: [{ id: 'a', text: 'primeiro', done: false }, { id: 'b', text: 'segundo', done: true }] },
    ]
    expect(excerptOf(blocks)).toBe('primeiro segundo')
    expect(excerptOf([blocks[0], blocks[1]])).toBe('')
    expect(excerptOf([{ id: 'x', type: 'paragraph', text: 'a'.repeat(1000) }])).toHaveLength(240)
    expect(blockText(blocks[1])).toBe('')
  })

  it('progresso do checklist soma todas as listas', () => {
    const item = (done: boolean) => ({ id: Math.random().toString(), text: 'x', done })
    expect(checklistProgress([])).toEqual({ done: 0, total: 0 })
    expect(checklistProgress([{ id: 'a', type: 'checklist', items: [item(true), item(false)] }, { id: 'b', type: 'checklist', items: [item(true)] }])).toEqual({ done: 2, total: 3 })
  })

  it('ago descreve o tempo em português, sem negativos', () => {
    const now = 1_000_000_000_000
    expect(ago(now + 5000, now)).toBe('agora há pouco')
    expect(ago(now - 90_000, now)).toBe('há 2 min')
    expect(ago(now - 2 * 3_600_000, now)).toBe('há 2 h')
    expect(ago(now - 3 * 86_400_000, now)).toBe('há 3 d')
    expect(ago(now - 35 * 86_400_000, now)).toBe('há 1 mês')
    expect(ago(now - 60 * 86_400_000, now)).toBe('há 2 meses')
    expect(ago(now - 100 * 86_400_000, now)).toBe('há 3 meses')
  })

  it('conta palavras sem se enganar com espaços, quebras e texto vazio', () => {
    expect(wordCount('')).toBe(0)
    expect(wordCount('   \n\t ')).toBe(0)
    expect(wordCount('uma palavra')).toBe(2)
    expect(wordCount('  muitos   espaços\ne\nquebras  ')).toBe(4)
    expect(wordCount('a '.repeat(100_000))).toBe(100_000)
  })

  it('estatísticas: o bloco seguro nunca conta; o tempo de leitura sobe de 200 em 200 palavras', () => {
    const blocks: Block[] = [
      { id: '1', type: 'paragraph', text: 'um dois três' },
      { id: '2', type: 'secure', text: 'segredo que não conta' },
      { id: '3', type: 'checklist', items: [{ id: 'a', text: 'item um', done: false }] },
    ]
    expect(pageStats(blocks)).toEqual({ words: 5, chars: 'um dois três'.length + 'item um'.length, minutes: 1 })
    expect(pageStats([])).toEqual({ words: 0, chars: 0, minutes: 0 })
    const big: Block[] = [{ id: 'x', type: 'paragraph', text: 'a '.repeat(401) }]
    expect(pageStats(big).minutes).toBe(3)
    expect(pageStats([{ id: 'x', type: 'paragraph', text: 'a '.repeat(200) }]).minutes).toBe(1)
  })

  it('o sumário só tem títulos, na ordem, e título vazio vira "Sem título"', () => {
    const blocks: Block[] = [
      { id: 'h1', type: 'heading', text: '  Primeiro \n título ' },
      { id: 'p', type: 'paragraph', text: 'texto' },
      { id: 'h2', type: 'heading', text: '   ' },
    ]
    expect(outline(blocks)).toEqual([{ id: 'h1', text: 'Primeiro título' }, { id: 'h2', text: 'Sem título' }])
    expect(outline([])).toEqual([])
  })
})
