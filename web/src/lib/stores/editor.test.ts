import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { MAX_BLOCKS, MAX_COLS, MAX_COL_WIDTH, MAX_ITEMS, MAX_ROWS, MAX_TEXT, MIN_COL_WIDTH, type Block } from './blocks'
import { PageEditor } from './editor.svelte'
import { Workspace } from './workspace.svelte'

let ws: Workspace
let ed: PageEditor
const kinds = () => ed.blocks.map((b) => b.type)
const table = () => ed.blocks.find((b) => b.type === 'table') as Extract<Block, { type: 'table' }>
const checklist = () => ed.blocks.find((b) => b.type === 'checklist') as Extract<Block, { type: 'checklist' }>

beforeEach(() => {
  vi.useFakeTimers()
  ws = new Workspace()
  ed = new PageEditor(ws, 'p0')
})
afterEach(() => {
  ed.destroy()
  vi.useRealTimers()
})

describe('PageEditor — blocos', () => {
  it('abre a página do design com os sete blocos, na ordem', () => {
    expect(kinds()).toEqual(['heading', 'paragraph', 'checklist', 'code', 'spoiler', 'secure', 'table'])
    expect(ed.progress).toEqual({ done: 2, total: 4 })
  })

  it('uma página nunca aberta começa como um parágrafo com o resumo; uma vazia começa vazia', () => {
    const other = new PageEditor(ws, 'p5')
    expect(other.blocks).toHaveLength(1)
    expect(other.blocks[0]).toMatchObject({ type: 'paragraph', text: expect.stringContaining('Levain') })
    const fresh = ws.newPage()
    expect(new PageEditor(ws, fresh.id).blocks).toEqual([])
    expect(new PageEditor(ws, 'nao-existe').blocks).toEqual([])
  })

  it('insere depois do bloco pedido, ou no fim', () => {
    const first = ed.blocks[0].id
    const made = ed.insert('paragraph', first)!
    expect(ed.blocks[1].id).toBe(made.id)
    const last = ed.insert('code')!
    expect(ed.blocks.at(-1)!.id).toBe(last.id)
    expect(ed.insert('paragraph', 'nao-existe')).not.toBeNull() // unknown anchor: goes to the end, never lost
  })

  it('não passa do limite de blocos', () => {
    for (let i = 0; i < MAX_BLOCKS + 20; i++) ed.insert('paragraph')
    expect(ed.blocks).toHaveLength(MAX_BLOCKS)
    expect(ed.insert('heading')).toBeNull()
  })

  it('remove e move; mover para fora da lista não faz nada', () => {
    const [a, b] = ed.blocks.map((x) => x.id)
    ed.moveBy(a, 1)
    expect(ed.blocks.slice(0, 2).map((x) => x.id)).toEqual([b, a])
    ed.moveBy(b, -1) // already first
    expect(ed.blocks[0].id).toBe(b)
    ed.moveBy(ed.blocks.at(-1)!.id, 1)
    ed.move(0, 99)
    expect(ed.blocks).toHaveLength(7)
    ed.remove(a)
    ed.remove('nao-existe')
    expect(ed.blocks).toHaveLength(6)
  })

  it('texto passa do limite é cortado; bloco sem texto ignora', () => {
    const id = ed.blocks[1].id
    ed.setText(id, 'x'.repeat(MAX_TEXT + 500))
    expect((ed.blocks[1] as { text: string }).text).toHaveLength(MAX_TEXT)
    ed.setText(checklist().id, 'não deve fazer nada')
    ed.setText('nao-existe', 'x')
  })

  it('Enter no meio do parágrafo divide: o resto vira um parágrafo novo logo depois', () => {
    const p = ed.blocks[1]
    ed.setText(p.id, 'abcdef')
    const made = ed.split(p.id, 2)!
    expect((ed.blocks[1] as { text: string }).text).toBe('ab')
    expect((made as { text: string }).text).toBe('cdef')
    expect(ed.blocks[2].id).toBe(made.id)
    // caret out of range is clamped; a block that cannot be split says so
    expect(ed.split(p.id, -5)).not.toBeNull()
    expect(ed.split(p.id, 9999)).not.toBeNull()
    expect(ed.split(checklist().id, 0)).toBeNull()
  })

  it('o resumo do cartão, a contagem e a data seguem a edição', () => {
    const before = ws.page('p0')!.updated
    vi.setSystemTime(Date.now() + 60_000)
    ed.setText('r1', 'Novo título da seção')
    const p = ws.page('p0')!
    expect(p.excerpt).toBe('Novo título da seção')
    expect(p.blocks).toBe(7)
    expect(p.updated).toBeGreaterThan(before)
  })

  it('o indicador de salvamento passa por "salvando" e volta para "salvo"', () => {
    expect(ed.save).toBe('saved')
    ed.setText('r2', 'x')
    expect(ed.save).toBe('saving')
    ed.setText('r2', 'xy')
    vi.advanceTimersByTime(400)
    expect(ed.save).toBe('saving') // typing keeps pushing the "saved" moment back
    vi.advanceTimersByTime(300)
    expect(ed.save).toBe('saved')
  })

  it('título: espaços e quebras viram um espaço, e tem limite', () => {
    ed.setTitle('  Uma\n\n  nota   ')
    expect(ws.page('p0')!.title).toBe(' Uma nota ')
    ed.setTitle('t'.repeat(500))
    expect(ws.page('p0')!.title).toHaveLength(120)
  })
})

describe('PageEditor — checklist', () => {
  it('marca, edita, adiciona depois de um item e remove', () => {
    const c = checklist()
    ed.toggleItem(c.id, 'i3')
    expect(ed.progress.done).toBe(3)
    ed.toggleItem(c.id, 'i3')
    ed.setItemText(c.id, 'i1', 'novo texto')
    expect(c.items[0].text).toBe('novo texto')
    const added = ed.addItem(c.id, 'i1')!
    expect(c.items[1].id).toBe(added)
    ed.removeItem(c.id, added)
    expect(c.items).toHaveLength(4)
    ed.toggleItem(c.id, 'nao-existe')
  })

  it('tirar o último item leva o bloco junto; a lista tem limite', () => {
    const b = ed.insert('checklist')!
    if (b.type !== 'checklist') throw new Error()
    for (let i = 0; i < MAX_ITEMS + 10; i++) ed.addItem(b.id)
    expect(b.items).toHaveLength(MAX_ITEMS)
    expect(ed.addItem(b.id)).toBeNull()
    const solo = ed.insert('checklist')!
    if (solo.type !== 'checklist') throw new Error()
    ed.removeItem(solo.id, solo.items[0].id)
    expect(ed.blocks.some((x) => x.id === solo.id)).toBe(false)
  })
})

describe('PageEditor — tabela', () => {
  it('edita rótulos e células; linha e coluna novas vêm vazias e completas', () => {
    const t = table()
    ed.setLabel(t.id, 'c1', 'Área')
    ed.setCell(t.id, 0, 'c2', 'Ana')
    ed.setCell(t.id, 99, 'c2', 'fora') // no such row: ignored
    expect(t.cols[0].label).toBe('Área')
    expect(t.rows[0].c2).toBe('Ana')
    ed.addRow(t.id)
    expect(t.rows.at(-1)).toEqual({ c1: '', c2: '', c3: '' })
    const col = ed.addCol(t.id)!
    expect(t.rows.every((r) => r[col] === '')).toBe(true)
  })

  it('sempre fica ao menos uma coluna e uma linha; limites de tamanho', () => {
    const t = table()
    for (const c of ['c1', 'c2']) ed.removeCol(t.id, c)
    ed.removeCol(t.id, 'c3')
    expect(t.cols).toHaveLength(1)
    expect(t.rows.every((r) => !('c1' in r) && !('c2' in r))).toBe(true)
    for (let i = 0; i < 5; i++) ed.removeRow(t.id, 0)
    expect(t.rows).toHaveLength(1)
    for (let i = 0; i < MAX_COLS + 5; i++) ed.addCol(t.id)
    expect(t.cols).toHaveLength(MAX_COLS)
    for (let i = 0; i < MAX_ROWS + 5; i++) ed.addRow(t.id)
    expect(t.rows).toHaveLength(MAX_ROWS)
  })

  it('largura fica entre o mínimo e o máximo, e ignora valores absurdos', () => {
    const t = table()
    ed.resizeCol(t.id, 'c1', 5)
    expect(t.cols[0].w).toBe(MIN_COL_WIDTH)
    ed.resizeCol(t.id, 'c1', 99999)
    expect(t.cols[0].w).toBe(MAX_COL_WIDTH)
    ed.resizeCol(t.id, 'c1', Number.NaN)
    ed.resizeCol(t.id, 'c1', Infinity)
    expect(t.cols[0].w).toBe(MAX_COL_WIDTH)
  })

  it('reordena colunas e linhas sem perder o conteúdo', () => {
    const t = table()
    ed.moveCol(t.id, 0, 3)
    expect(t.cols.map((c) => c.id)).toEqual(['c2', 'c3', 'c1'])
    expect(t.rows[0]).toMatchObject({ c1: 'Conciliação', c2: 'Marina' })
    ed.moveRow(t.id, 2, 0)
    expect(t.rows[0].c1).toBe('Relatório do conselho')
  })
})

describe('PageEditor — tags, imagem, secreto, lixeira', () => {
  it('adiciona tag existente, cria nova com cor, não duplica e remove', () => {
    expect(ed.addTag('leitura')).toBe(true)
    expect(ed.addTag('LEITURA')).toBe(false)
    expect(ed.addTag('   ')).toBe(false)
    expect(ed.addTag('Nova Ideia', 'plum')).toBe(true)
    expect(ws.tag('nova-ideia')).toMatchObject({ color: 'plum' })
    expect(ws.page('p0')!.tags).toContain('nova-ideia')
    ed.removeTag('nova-ideia')
    ed.removeTag('nao-tem')
    expect(ws.page('p0')!.tags).not.toContain('nova-ideia')
  })

  it('trocar a imagem solta a URL antiga', () => {
    const revoke = vi.fn()
    URL.revokeObjectURL = revoke
    const img = ed.insert('image')!
    ed.setImage(img.id, 'a.png', 'blob:a')
    ed.setImage(img.id, 'b.png', 'blob:b')
    expect(revoke).toHaveBeenCalledWith('blob:a')
    ed.setImage(img.id, null, null)
    expect(revoke).toHaveBeenCalledWith('blob:b')
  })

  it('spoiler e bloco seguro começam fechados', () => {
    expect(ed.revealed).toEqual({})
    ed.reveal('r5', true)
    expect(ed.revealed.r5).toBe(true)
  })

  it('página na lixeira não aceita nenhuma edição', () => {
    ws.trash('p0')
    expect(ed.readOnly).toBe(true)
    const snapshot = JSON.stringify(ws.page('p0')!.content)
    const title = ws.page('p0')!.title
    ed.setTitle('x')
    ed.setText('r2', 'x')
    ed.insert('paragraph')
    ed.remove('r1')
    ed.moveBy('r1', 1)
    ed.toggleItem('r3', 'i3')
    ed.addRow('r7')
    ed.addTag('leitura')
    ed.setLang('r4', 'go')
    expect(JSON.stringify(ws.page('p0')!.content)).toBe(snapshot)
    expect(ws.page('p0')!.title).toBe(title)
    ws.restore('p0')
    ed.setText('r2', 'agora sim')
    expect((ed.blocks[1] as { text: string }).text).toBe('agora sim')
  })
})

describe('PageEditor — permissões de quem recebeu a página', () => {
  const as = (id: string) => new PageEditor(ws, id)

  it('o dono pode tudo; só leitura não muda nada; o resto segue a lista', () => {
    expect(ed.isOwner).toBe(true)
    expect(['text', 'share', 'delete', 'images'].every((k) => ed.can(k as never))).toBe(true)
    const read = as('s2')
    expect(read.isOwner).toBe(false)
    expect(read.can('text')).toBe(false)
    expect(read.can('export')).toBe(false)
    const limited = as('s3')
    expect(limited.can('text')).toBe(true)
    expect(limited.can('share')).toBe(false)
    expect(limited.can('images')).toBe(false)
    expect(as('nao-existe').can('text')).toBe(false)
  })

  it('só leitura: nenhuma edição passa', () => {
    const read = as('s2')
    const before = JSON.stringify(ws.page('s2'))
    read.setTitle('x')
    read.setText(read.blocks[0].id, 'x')
    read.insert('paragraph')
    read.remove(read.blocks[0].id)
    read.addTag('leitura')
    read.setImage('x', 'a', 'b')
    expect(JSON.stringify(ws.page('s2'))).toBe(before)
  })

  it('cada permissão libera só o que diz', () => {
    const textOnly = (perms: string[]) => {
      ws.page('s3')!.myPerms = perms as never
      return as('s3')
    }
    const t = textOnly(['text'])
    t.setText(t.blocks[0].id, 'novo texto')
    expect((t.blocks[0] as { text: string }).text).toBe('novo texto')
    expect(t.insert('paragraph')).toBeNull() // no "blocks"
    expect(t.addTag('leitura')).toBe(false) // no "tags"
    const b = textOnly(['blocks'])
    expect(b.insert('paragraph')).not.toBeNull()
    expect(b.insert('image')).toBeNull() // blocks yes, images no
    const bi = textOnly(['blocks', 'images'])
    expect(bi.insert('image')).not.toBeNull()
    const tg = textOnly(['tags'])
    expect(tg.addTag('leitura')).toBe(true)
    tg.setTitle('x')
    expect(ws.page('s3')!.title).not.toBe('x')
  })

  it('marcar checklist e mexer na tabela têm permissão própria', () => {
    ws.page('s3')!.content = [
      { id: 'c', type: 'checklist', items: [{ id: 'i', text: 'a', done: false }] },
      { id: 't', type: 'table', cols: [{ id: 'k', label: 'K', w: 100 }], rows: [{ k: 'v' }] },
    ]
    ws.page('s3')!.myPerms = ['checklist']
    const e = as('s3')
    e.toggleItem('c', 'i')
    expect((e.blocks[0] as { items: { done: boolean }[] }).items[0].done).toBe(true)
    e.setItemText('c', 'i', 'mudou')
    e.addRow('t')
    e.setCell('t', 0, 'k', 'x')
    expect((e.blocks[1] as { rows: Record<string, string>[] }).rows).toEqual([{ k: 'v' }])
    ws.page('s3')!.myPerms = ['tables']
    e.addRow('t')
    expect((e.blocks[1] as { rows: unknown[] }).rows).toHaveLength(2)
    e.toggleItem('c', 'i')
    expect((e.blocks[0] as { items: { done: boolean }[] }).items[0].done).toBe(true) // unchanged: no "checklist"
  })

  it('compartilhar exige a permissão; retirar acesso é só do dono', () => {
    expect(ed.share(['tiago'], ['text'])).toBe(1)
    ed.setShare('tiago', ['tags'])
    expect(ws.page('p0')!.shares.find((s) => s.userId === 'tiago')!.perms).toEqual(['tags'])
    ed.unshare('tiago')
    expect(ws.page('p0')!.shares.some((s) => s.userId === 'tiago')).toBe(false)

    ws.page('s3')!.myPerms = ['share']
    const guest = as('s3')
    expect(guest.share(['tiago'], [])).toBe(1) // a guest with "share" may add people...
    guest.setShare('tiago', ['text'])
    guest.unshare('tiago')
    guest.unshareAll()
    expect(ws.page('s3')!.shares).toEqual([{ userId: 'tiago', perms: [] }]) // ...but never change or take away access
    ws.page('s3')!.myPerms = []
    expect(as('s3').share(['tiago'], [])).toBe(0)
  })

  it('retirar de todos esvazia a lista', () => {
    expect(ed.shares).toHaveLength(2)
    ed.unshareAll()
    expect(ed.shares).toEqual([])
  })

  it('a lixeira trava até o dono, menos exportar e excluir', () => {
    ws.trash('p0')
    expect(ed.can('text')).toBe(false)
    expect(ed.can('share')).toBe(false)
    expect(ed.can('export')).toBe(true)
    expect(ed.can('delete')).toBe(true)
  })
})

describe('PageEditor — painel', () => {
  it('sumário, estatísticas e relacionadas acompanham a edição', () => {
    expect(ed.outline).toEqual([{ id: 'r1', text: 'O que precisa acontecer antes do dia 31' }])
    const before = ed.stats.words
    ed.setText('r2', 'uma palavra só')
    expect(ed.stats.words).toBeLessThan(before)
    ed.insert('heading', 'r2')
    expect(ed.outline).toHaveLength(2)
    expect(ed.related.length).toBeGreaterThan(0)
  })

  it('fixar vale para o dono e para quem recebeu; não na lixeira', () => {
    ed.togglePin()
    expect(ws.page('p0')!.pinned).toBe(true)
    ed.togglePin()
    expect(ws.page('p0')!.pinned).toBe(false)
    ws.trash('p0')
    ed.togglePin()
    expect(ws.page('p0')!.pinned).toBe(false)
  })

  it('duplicar precisa da permissão de exportar e não funciona na lixeira', () => {
    const made = ed.duplicate()!
    expect(ws.page(made.id)!.title).toContain('(cópia)')
    ws.page('s3')!.myPerms = ['text']
    expect(new PageEditor(ws, 's3').duplicate()).toBeNull()
    ws.page('s3')!.myPerms = ['export']
    expect(new PageEditor(ws, 's3').duplicate()).not.toBeNull()
    ws.trash('p0')
    expect(ed.duplicate()).toBeNull()
  })
})


describe('PageEditor — novos blocos, ícone e capa', () => {
  it('insere citação, destaque, toggle e divisor', () => {
    for (const t of ['quote', 'callout', 'toggle', 'divider'] as const) expect(ed.insert(t)?.type).toBe(t)
    expect(kinds().slice(-4)).toEqual(['quote', 'callout', 'toggle', 'divider'])
    const tg = ed.blocks.find((b) => b.type === 'toggle')!
    ed.setText(tg.id, 'Título')
    ed.setBody(tg.id, 'Corpo')
    expect(tg).toMatchObject({ text: 'Título', body: 'Corpo' })
  })

  it('o corpo do toggle conta nas palavras e na busca; o divisor não conta nada', () => {
    const before = ed.stats.words
    const tg = ed.insert('toggle')!
    ed.setText(tg.id, 'um dois')
    ed.setBody(tg.id, 'três')
    ed.insert('divider')
    expect(ed.stats.words).toBe(before + 3)
  })

  it('Enter numa citação cria um parágrafo com o resto do texto', () => {
    const q = ed.insert('quote')!
    ed.setText(q.id, 'abcdef')
    const made = ed.split(q.id, 3)
    expect(made).toMatchObject({ type: 'paragraph', text: 'def' })
    expect((ed.blocks.find((b) => b.id === q.id) as { text: string }).text).toBe('abc')
  })

  it('transforma texto em outro tipo de texto mantendo id e palavras', () => {
    const p = ed.blocks.find((b) => b.type === 'paragraph')!
    const text = (p as { text: string }).text
    expect(ed.turnInto(p.id, 'quote')).toBe(true)
    expect(ed.blocks.find((b) => b.id === p.id)).toMatchObject({ type: 'quote', text })
    expect(ed.turnInto(p.id, 'quote')).toBe(false)
    expect(ed.turnInto(p.id, 'toggle')).toBe(true)
    expect(ed.blocks.find((b) => b.id === p.id)).toMatchObject({ type: 'toggle', text, body: '' })
  })

  it('segredo, spoiler, checklist e tabela nunca viram outro tipo', () => {
    for (const type of ['secure', 'spoiler', 'checklist', 'table', 'code']) {
      const b = ed.blocks.find((x) => x.type === type)!
      expect(ed.turnInto(b.id, 'paragraph'), type).toBe(false)
      expect(ed.blocks.find((x) => x.id === b.id)!.type).toBe(type)
    }
  })

  it('duplica um bloco logo depois, com ids novos, sem tocar no original', () => {
    const list = checklist()
    const copy = ed.duplicateBlock(list.id) as Extract<Block, { type: 'checklist' }>
    expect(copy.id).not.toBe(list.id)
    expect(ed.blocks.indexOf(ed.blocks.find((b) => b.id === copy.id)!)).toBe(ed.blocks.findIndex((b) => b.id === list.id) + 1)
    expect(copy.items.map((i) => i.text)).toEqual(list.items.map((i) => i.text))
    expect(copy.items.some((i) => list.items.some((o) => o.id === i.id))).toBe(false)
    ed.toggleItem(copy.id, copy.items[0].id)
    expect(checklist().items[0].done).toBe(true)
    expect(ed.progress.total).toBe(8)
  })

  it('imagem não duplica, e o limite de blocos vale', () => {
    const img = ed.insert('image')!
    expect(ed.duplicateBlock(img.id)).toBeNull()
    expect(ed.duplicateBlock('nao-existe')).toBeNull()
    while (ed.blocks.length < MAX_BLOCKS) ed.insert('divider')
    expect(ed.duplicateBlock(ed.blocks[0].id)).toBeNull()
  })

  it('ícone: só um emoji; capa: só especificações que o app sabe desenhar', () => {
    ed.setIcon('🦄')
    expect(ed.page!.icon).toBe('🦄')
    for (const bad of ['<script>', 'abc', '🦄🦄', 'a🦄', '🦄 ', '<b>🦄</b>', '🦄'.repeat(30)]) {
      ed.setIcon(bad)
      expect(ed.page!.icon, bad).toBe('🦄')
    }
    ed.setIcon('🇧🇷')
    expect(ed.page!.icon).toBe('🇧🇷')
    ed.setIcon('')
    expect(ed.page!.icon).toBe('')

    for (const good of ['oceano', 'solid:verde', 'mono:ouro', 'duo:rosa:azul:r', 'mix:arco-iris']) {
      ed.setCover(good)
      expect(ed.page!.cover, good).toBe(good)
    }
    for (const bad of ['url(http://x)', 'solid:nao', 'duo:verde:azul', 'duo:verde:azul:x', 'mix:nada', 'mono:verde:x', 'javascript:alert(1)', 'solid:verde;background:red', 'x'.repeat(100)]) {
      ed.setCover(bad)
      expect(ed.page!.cover, bad).toBe('mix:arco-iris')
    }
    ed.setCover('')
    expect(ed.page!.cover).toBe('')
  })

  it('quem só pode ler (sem a permissão de texto) não muda ícone nem capa nem converte', () => {
    const guest = new PageEditor(ws, 's2')
    expect(guest.can('text')).toBe(false)
    guest.setIcon('🔥')
    guest.setCover('musgo')
    expect(guest.page).toMatchObject({ icon: '', cover: '' })
    guest.destroy()
  })

  it('página na lixeira não muda ícone nem capa', () => {
    ws.trash('p0')
    ed.setIcon('🔥')
    ed.setCover('noite')
    expect(ed.page!.icon).toBe('📋')
  })

  it('duplicar a página leva ícone e capa junto', () => {
    const made = ed.duplicate()!
    expect(ws.page(made.id)).toMatchObject({ icon: '📋', cover: 'musgo' })
  })
})
