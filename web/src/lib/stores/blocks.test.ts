import { describe, expect, it } from 'vitest'
import { MAX_INDENT, TONES, isDirectMedia, isUrlBlock, ago, blockText, isTextType, isTone, levelOf, numbering, outline, toneOf, pageStats, wordCount, checklistProgress, excerptOf, makeBlock, moveItem, newId, type Block } from './blocks'

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
    expect(outline(blocks)).toEqual([{ id: 'h1', text: 'Primeiro título', level: 2 }, { id: 'h2', text: 'Sem título', level: 2 }])
    expect(outline([])).toEqual([])
  })
})

describe('blocos novos: títulos de três tamanhos, listas, sumário e link', () => {
  it('um título antigo, sem nível, é o do meio; o menu cria os outros', () => {
    expect(levelOf({})).toBe(2)
    expect(makeBlock('heading')).toMatchObject({ type: 'heading', text: '' })
    expect('level' in makeBlock('heading')).toBe(false)
    expect(makeBlock('heading', { level: 1 })).toMatchObject({ level: 1 })
    expect(makeBlock('heading', { level: 3 })).toMatchObject({ level: 3 })
    expect('level' in makeBlock('heading', { level: 2 })).toBe(false)
  })

  it('cada tipo novo nasce vazio e válido', () => {
    expect(makeBlock('bullet')).toMatchObject({ type: 'bullet', text: '', indent: 0 })
    expect(makeBlock('numbered')).toMatchObject({ type: 'numbered', text: '', indent: 0 })
    expect(makeBlock('toc')).toMatchObject({ type: 'toc' })
    expect(makeBlock('bookmark')).toMatchObject({ type: 'bookmark', url: '', title: '' })
    expect(isTextType('bullet') && isTextType('numbered')).toBe(true)
    expect(isTextType('toc') || isTextType('bookmark')).toBe(false)
  })

  it('o texto de uma lista conta para o resumo e a busca; o sumário nunca; o link só pelo título', () => {
    expect(blockText({ id: 'a', type: 'bullet', text: 'um item' })).toBe('um item')
    expect(blockText({ id: 'a', type: 'numbered', text: 'outro' })).toBe('outro')
    expect(blockText({ id: 'a', type: 'toc' })).toBe('')
    expect(blockText({ id: 'a', type: 'bookmark', url: 'https://a.com', title: 'Site' })).toBe('Site')
    expect(excerptOf([{ id: 'a', type: 'toc' }, { id: 'b', type: 'bullet', text: 'primeiro item' }])).toBe('primeiro item')
  })

  it('o sumário traz o tamanho de cada título', () => {
    const blocks: Block[] = [
      { id: 'a', type: 'heading', text: 'Grande', level: 1 },
      { id: 'b', type: 'heading', text: 'Médio' },
      { id: 'c', type: 'heading', text: 'Pequeno', level: 3 },
    ]
    expect(outline(blocks).map((o) => o.level)).toEqual([1, 2, 3])
  })

  it('tons de destaque: o padrão é a nota, e só os quatro existem', () => {
    expect(toneOf({})).toBe('info')
    expect(TONES.map((t) => t.key)).toEqual(['info', 'success', 'warning', 'danger'])
    expect(isTone('warning') && !isTone('rosa') && !isTone(undefined) && !isTone(1)).toBe(true)
  })
})

describe('numeração das listas', () => {
  const n = (type: 'numbered' | 'bullet' | 'paragraph', id: string, indent = 0): Block => (type === 'paragraph' ? { id, type, text: '' } : { id, type, text: '', indent })

  it('conta de um em um e recomeça depois de qualquer bloco que não seja da lista', () => {
    const out = numbering([n('numbered', 'a'), n('numbered', 'b'), n('paragraph', 'p'), n('numbered', 'c'), n('numbered', 'd')])
    expect([...out.values()]).toEqual([1, 2, 1, 2])
  })

  it('um nível mais fundo conta por conta própria e recomeça sob cada item novo', () => {
    const out = numbering([n('numbered', 'a'), n('numbered', 'a1', 1), n('numbered', 'a2', 1), n('numbered', 'b'), n('numbered', 'b1', 1), n('numbered', 'c')])
    expect([...out.entries()]).toEqual([['a', 1], ['a1', 1], ['a2', 2], ['b', 2], ['b1', 1], ['c', 3]])
  })

  it('um item com marcador entre os numerados corta a contagem do nível dele, mas não a do nível de fora', () => {
    const out = numbering([n('numbered', 'a'), n('bullet', 'x', 1), n('numbered', 'b'), n('bullet', 'y'), n('numbered', 'c')])
    expect([...out.entries()]).toEqual([['a', 1], ['b', 2], ['c', 1]])
  })

  it('um item que pula níveis, ou um nível fora do limite, não quebra a conta', () => {
    const out = numbering([n('numbered', 'a', 3), n('numbered', 'b', 99), n('numbered', 'c', -4)])
    expect(out.get('a')).toBe(1)
    expect(out.get('b')).toBe(2)
    expect(out.get('c')).toBe(1)
    expect(MAX_INDENT).toBe(3)
    expect(numbering([]).size).toBe(0)
  })

  it('é rápida mesmo com a página cheia', () => {
    const blocks = Array.from({ length: 500 }, (_, i) => n('numbered', `n${i}`, i % 4))
    const t0 = performance.now()
    for (let i = 0; i < 200; i++) numbering(blocks)
    expect(performance.now() - t0).toBeLessThan(1000)
  })
})

describe('título com toggle', () => {
  it('nasce com o texto escondido vazio, em qualquer tamanho, e o texto escondido conta para a busca', () => {
    expect(makeBlock('heading', { level: 3, toggle: true })).toMatchObject({ type: 'heading', level: 3, toggle: true, body: '' })
    expect(makeBlock('heading', { toggle: true })).toMatchObject({ toggle: true, body: '' })
    expect('toggle' in makeBlock('heading', { level: 1 })).toBe(false)
    expect(blockText({ id: 'a', type: 'heading', text: 'Seção', toggle: true, body: 'dentro' })).toBe('Seção dentro')
    expect(blockText({ id: 'a', type: 'heading', text: 'Seção' })).toBe('Seção')
  })
})

describe('link para página, vídeo, áudio e PDF', () => {
  it('nascem vazios e válidos', () => {
    expect(makeBlock('pagelink')).toMatchObject({ type: 'pagelink', pageId: '', title: '' })
    for (const t of ['video', 'audio', 'pdf'] as const) expect(makeBlock(t)).toMatchObject({ type: t, url: '', title: '' })
    expect(isUrlBlock(makeBlock('video')) && isUrlBlock(makeBlock('bookmark')) && !isUrlBlock(makeBlock('pagelink')) && !isUrlBlock(makeBlock('image'))).toBe(true)
  })

  it('o título deles entra no resumo e na busca, o endereço não', () => {
    expect(blockText({ id: 'a', type: 'video', url: 'https://a.com/v.mp4', title: 'Aula' })).toBe('Aula')
    expect(blockText({ id: 'a', type: 'pdf', url: 'https://a.com/x.pdf', title: '' })).toBe('')
    expect(blockText({ id: 'a', type: 'pagelink', pageId: 'p1', title: 'Outra' })).toBe('Outra')
  })

  it('só um endereço direto para um arquivo toca; uma página de player (YouTube) não', () => {
    expect(isDirectMedia('video', 'https://a.com/x/aula.MP4?token=1')).toBe(true)
    expect(isDirectMedia('video', 'https://a.com/aula.webm')).toBe(true)
    expect(isDirectMedia('video', 'https://www.youtube.com/watch?v=abc')).toBe(false)
    expect(isDirectMedia('video', 'https://a.com/aula.mp3')).toBe(false)
    expect(isDirectMedia('audio', 'https://a.com/som.mp3')).toBe(true)
    expect(isDirectMedia('audio', 'https://a.com/som.flac')).toBe(true)
    expect(isDirectMedia('audio', 'https://a.com/aula.mp4')).toBe(false)
    expect(isDirectMedia('audio', 'não é endereço.mp3')).toBe(false)
    expect(isDirectMedia('video', '')).toBe(false)
  })
})

