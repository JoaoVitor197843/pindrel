import { flushSync } from 'svelte'
import { describe, expect, it } from 'vitest'
import type { Block } from './blocks'
import { fold, formatDate, pageMeta, Workspace } from './workspace.svelte'

const titles = (w: Workspace) => w.visible.map((p) => p.title)

describe('Workspace', () => {
  it('conta páginas por visão (as compartilhadas ficam fora de "todas") e por tag', () => {
    const w = new Workspace()
    expect(w.counts).toEqual({ all: 23, shared: 3, vault: 5, trash: 0 })
    expect(w.tagCounts).toMatchObject({ trabalho: 6, pessoal: 10, receitas: 3, servidor: 4 })
  })

  it('ordena por recentes e por A–Z', () => {
    const w = new Workspace()
    expect(w.visible[0].title).toBe('Reforma do apartamento — orçamento')
    w.sort = 'az'
    expect(titles(w)[0]).toBe('Anotações do curso de tipografia')
  })

  it('busca ignora acento e caixa, e olha o resumo também', () => {
    const w = new Workspace()
    w.query = 'MIGRACAO'
    expect(titles(w)).toEqual(['Migração do servidor para NixOS'])
    w.query = 'levain'
    expect(titles(w)).toEqual(['Pão de fermentação natural'])
    w.query = '   '
    expect(w.visible).toHaveLength(23)
    w.query = 'zzzz'
    expect(w.visible).toEqual([])
  })

  it('filtra por tag, e trocar de visão limpa o filtro', () => {
    const w = new Workspace()
    w.toggleTagFilter('receitas')
    expect(w.visible).toHaveLength(3)
    w.toggleTagFilter('receitas')
    expect(w.visible).toHaveLength(23)
    w.toggleTagFilter('receitas')
    w.go('shared')
    expect(w.tagFilter).toBeNull()
    expect(titles(w).sort()).toEqual(['Plano de mudança — casa nova', 'Retro da sprint 14 (equipe)', 'Runbook de incidentes'])
  })

  it('escolher uma tag estando nas compartilhadas volta para "todas"', () => {
    const w = new Workspace()
    w.go('shared')
    w.toggleTagFilter('trabalho')
    expect(w.view).toBe('all')
    expect(w.visible).toHaveLength(6)
  })

  it('nova página entra no topo, limpa busca e herda a tag filtrada', () => {
    const w = new Workspace()
    w.query = 'xyz'
    w.go('trash')
    w.toggleTagFilter('pessoal')
    const p = w.newPage()
    expect(w.view).toBe('all')
    expect(w.query).toBe('')
    expect(w.visible[0].id).toBe(p.id)
    expect(p.tags).toEqual(['pessoal'])
    expect(w.newPage('   ').title).toBe('Sem título')
    expect(w.newPage('x'.repeat(500)).title).toHaveLength(120)
  })

  it('ids de páginas novas nunca se repetem, mesmo com cliques repetidos', () => {
    const w = new Workspace()
    const ids = new Set(Array.from({ length: 200 }, () => w.newPage().id))
    expect(ids.size).toBe(200)
  })

  it('lixeira: mover, restaurar e esvaziar', () => {
    const w = new Workspace()
    w.trash('p1')
    w.trash('inexistente')
    expect(w.counts).toMatchObject({ all: 22, trash: 1 })
    w.go('trash')
    expect(titles(w)).toEqual(['Reforma do apartamento — orçamento'])
    w.restore('p1')
    expect(w.counts.trash).toBe(0)
    w.trash('p1')
    w.emptyTrash()
    expect(w.pages).toHaveLength(25)
    expect(w.counts.trash).toBe(0)
  })

  it('com a lixeira desligada, excluir apaga de vez', () => {
    const w = new Workspace()
    w.saveSettings({ useTrash: false, retention: 30 })
    w.trash('p1')
    expect(w.pages.some((p) => p.id === 'p1')).toBe(false)
    expect(w.counts.trash).toBe(0)
  })

  it('configurações: retenção fica entre 7 e 90 dias, mesmo com valor absurdo', () => {
    const w = new Workspace()
    w.saveSettings({ useTrash: true, retention: 1000 })
    expect(w.settings.retention).toBe(90)
    w.saveSettings({ useTrash: true, retention: 3 })
    expect(w.settings.retention).toBe(7)
    w.saveSettings({ useTrash: true, retention: Number.NaN })
    expect(w.settings.retention).toBe(30)
  })

  it('tags: cria com cor, normaliza espaços, não duplica e ignora vazio', () => {
    const w = new Workspace()
    expect(w.addTag('   ')).toBeNull()
    const t = w.addTag('  Minha  tag ', 'gold')!
    expect(t).toMatchObject({ name: 'minha-tag', color: 'gold' })
    expect(w.addTag('MINHA-TAG', 'rust')!.id).toBe(t.id)
    expect(w.tags.filter((x) => x.id === t.id)).toHaveLength(1)
    expect(w.addTag('a'.repeat(100))!.name).toHaveLength(24)
    // @ts-expect-error a color that does not exist falls back to the default
    expect(w.addTag('outra', 'neon')!.color).toBe('accent')
  })

  it('cofre: senha curta não abre; só aceita entrada nova desbloqueado; bloqueado não busca no conteúdo', () => {
    const w = new Workspace()
    expect(w.unlockVault('abc')).toBe('short')
    expect(w.unlockVault('   ab  ')).toBe('short')
    expect(w.vaultUnlocked).toBe(false)
    expect(w.addVaultEntry()).toBeNull()
    w.query = 'passaporte FG'
    expect(w.visibleVault).toEqual([])
    expect(w.unlockVault('abcd')).toBe('ok')
    expect(w.visibleVault).toHaveLength(1)
    w.query = ''
    expect(w.addVaultEntry()).not.toBeNull()
    flushSync()
    expect(w.counts.vault).toBe(6)
    w.lockVault()
    expect(w.vaultUnlocked).toBe(false)
  })

  it('grupos: fixadas primeiro, depois por data; A–Z não agrupa por data; busca e lixeira ficam planas', () => {
    const w = new Workspace()
    expect(w.groups.map((g) => g.key)).toEqual(['pinned', 'today', 'week', 'month', 'older'])
    expect(w.groups[0].pages.map((p) => p.id).sort()).toEqual(['p2', 'p6'])
    expect(w.groups.flatMap((g) => g.pages)).toHaveLength(23) // every page exactly once
    w.sort = 'az'
    expect(w.groups.map((g) => g.label)).toEqual(['Fixadas', 'Outras'])
    w.query = 'a'
    expect(w.groups).toHaveLength(1)
    expect(w.groups[0].label).toBeNull()
    w.query = ''
    w.togglePin('p2')
    w.togglePin('p6')
    w.togglePin('nao-existe')
    expect(w.groups.map((g) => g.label)).toEqual([null])
    w.go('trash')
    expect(w.groups[0].label).toBeNull()
  })

  it('reveal leva até a página: a visão certa, sem filtro, com o título na busca', () => {
    const w = new Workspace()
    w.toggleTagFilter('pessoal')
    w.reveal('s1')
    expect(w.view).toBe('shared')
    expect(w.tagFilter).toBeNull()
    expect(titles(w)).toEqual(['Retro da sprint 14 (equipe)'])
    w.reveal('nao-existe')
    expect(w.view).toBe('shared')
    w.trash('p1')
    w.reveal('p1')
    expect(w.view).toBe('trash')
  })

  it('limpar filtros zera busca e tag', () => {
    const w = new Workspace()
    w.query = 'x'
    w.tagFilter = 'pessoal'
    w.clearFilters()
    expect([w.query, w.tagFilter]).toEqual(['', null])
  })

  it('pageMeta, fold e formatDate', () => {
    const w = new Workspace()
    const by = (id: string) => w.pages.find((p) => p.id === id)!
    expect(pageMeta(by('p4'))).toBe('cofre')
    expect(pageMeta(by('s1'))).toBe('por Caio')
    expect(pageMeta(by('p1'))).toBe('4 blocos')
    expect(pageMeta({ ...by('p1'), blocks: 1 })).toBe('1 bloco')
    expect(fold('Ação')).toBe('acao')
    expect(formatDate(new Date(2025, 2, 9, 12).getTime())).toBe('09 mar 2025')
  })

  describe('cofre com páginas', () => {
    it('as entradas do cofre são páginas protegidas, também listadas em "todas"', () => {
      const w = new Workspace()
      expect(w.visibleVault.map((p) => p.id).sort()).toEqual(['p4', 'v2', 'v3', 'v4', 'v5'])
      expect(w.visibleVault.every((p) => p.locked)).toBe(true)
      expect(w.visible.filter((p) => p.locked)).toHaveLength(5)
    })

    it('trancado, a busca só olha o título; destrancado, olha o conteúdo', () => {
      const w = new Workspace()
      w.query = 'passaporte'
      expect(titles(w)).toEqual(['Documentos — RG, CPF, passaporte']) // by title
      w.query = 'FG882301'
      expect(w.visible).toEqual([])
      expect(w.visibleVault).toEqual([])
      w.unlockVault('abcd')
      expect(titles(w)).toEqual(['Documentos — RG, CPF, passaporte'])
      expect(w.visibleVault).toHaveLength(1)
    })

    it('uma página do cofre nunca fica na lixeira: some de vez, mesmo com a lixeira ligada', () => {
      const w = new Workspace()
      w.trash('v2')
      expect(w.page('v2')).toBeUndefined()
      expect(w.counts.trash).toBe(0)
      expect(w.counts.vault).toBe(4)
    })

    it('nova entrada segura é uma página protegida, só com o cofre aberto, e fica no cofre', () => {
      const w = new Workspace()
      expect(w.addVaultEntry()).toBeNull()
      w.unlockVault('abcd')
      const made = w.addVaultEntry()!
      expect(made).toMatchObject({ locked: true, title: 'Nova entrada segura' })
      expect(w.view).toBe('vault')
      expect(w.counts.vault).toBe(6)
      expect(w.visibleVault[0].id).toBe(made.id)
    })

    it('deleteForever apaga sem deixar rastro', () => {
      const w = new Workspace()
      w.deleteForever('p1')
      w.deleteForever('nao-existe')
      expect(w.page('p1')).toBeUndefined()
      expect(w.counts.trash).toBe(0)
    })
  })

  describe('compartilhamento', () => {
    it('compartilha com quem existe, ignora você mesmo, repetidos e desconhecidos', () => {
      const w = new Workspace()
      expect(w.sharePage('p1', ['tiago', 'tiago', 'me', 'ninguem', 'bea'], ['text', 'x' as never])).toBe(2)
      expect(w.page('p1')!.shares).toEqual([
        { userId: 'tiago', perms: ['text'] },
        { userId: 'bea', perms: ['text'] },
      ])
      expect(w.sharePage('p1', ['tiago'], [])).toBe(0)
      expect(w.sharePage('nao-existe', ['caio'], [])).toBe(0)
    })

    it('uma página que recebi aceita convidados (a permissão de compartilhar é checada no editor)', () => {
      const w = new Workspace()
      expect(w.sharePage('s1', ['tiago'], [])).toBe(1)
    })

    it('muda a permissão, retira um e retira todos', () => {
      const w = new Workspace()
      w.setShare('p0', 'julia', ['tags', 'tags', 'text'])
      expect(w.page('p0')!.shares.find((s) => s.userId === 'julia')!.perms).toEqual(['text', 'tags'])
      w.setShare('p0', 'ninguem', ['text'])
      w.unshare('p0', 'caio')
      expect(w.page('p0')!.shares.map((s) => s.userId)).toEqual(['julia'])
      w.unshareAll('p0')
      expect(w.page('p0')!.shares).toEqual([])
    })

    it('cada compartilhamento guarda uma cópia: mudar um não muda os outros', () => {
      const w = new Workspace()
      w.sharePage('p1', ['tiago', 'bea'], ['text'])
      w.setShare('p1', 'tiago', ['tags'])
      expect(w.page('p1')!.shares.find((s) => s.userId === 'bea')!.perms).toEqual(['text'])
    })

    it('páginas que recebi trazem o que posso fazer com elas', () => {
      const w = new Workspace()
      expect(w.page('s1')!.myPerms).toHaveLength(10)
      expect(w.page('s2')!.myPerms).toEqual([])
      expect(w.page('s3')!.myPerms).not.toContain('share')
      expect(w.page('p1')!.myPerms).toHaveLength(10)
    })
  })

  describe('relacionadas e duplicar', () => {
    it('relacionadas: quem divide mais tags vem primeiro; sem a própria página nem páginas do cofre', () => {
      const w = new Workspace()
      const ids = w.related('p0').map((p) => p.id)
      expect(ids).not.toContain('p0')
      expect(w.related('p0').every((p) => !p.locked)).toBe(true)
      // p8 shares "servidor" + "pessoal" with p13? p2 shares "servidor" + "trabalho" with p6? check the order rule instead
      const list = w.related('p2', 20)
      const overlap = (p: { tags: string[] }) => p.tags.filter((t) => w.page('p2')!.tags.includes(t)).length
      expect(list.length).toBeGreaterThan(1)
      for (let i = 1; i < list.length; i++) expect(overlap(list[i - 1])).toBeGreaterThanOrEqual(overlap(list[i]))
      expect(w.related('p2', 2)).toHaveLength(2)
    })

    it('sem tags ou página inexistente: nenhuma relacionada', () => {
      const w = new Workspace()
      expect(w.related('nao-existe')).toEqual([])
      const fresh = w.newPage()
      expect(w.related(fresh.id)).toEqual([])
    })

    it('uma página na lixeira não é sugerida', () => {
      const w = new Workspace()
      const first = w.related('p2')[0]
      w.trash(first.id)
      expect(w.related('p2').some((p) => p.id === first.id)).toBe(false)
    })

    it('duplicar cria uma cópia minha, sem compartilhamento, sem fixar, com ids novos', () => {
      const w = new Workspace()
      w.page('p0')!.pinned = true
      const made = w.duplicate('p0')!
      const copy = made.page
      expect(copy.id).not.toBe('p0')
      expect(copy.title).toBe('Rotina de encerramento do trimestre (cópia)')
      expect(copy.tags).toEqual(w.page('p0')!.tags)
      expect(copy.shares).toEqual([])
      expect(copy.pinned).toBe(false)
      expect(copy.sharedBy).toBeNull()
      expect(copy.content).toHaveLength(7)
      const original = w.page('p0')!.content!.map((b) => b.id)
      expect(copy.content!.every((b) => !original.includes(b.id))).toBe(true)
      expect(w.pages[0].id).toBe(copy.id)
      expect(made.images).toBe(0)
    })

    it('mexer na cópia não mexe no original (nada é compartilhado por referência)', () => {
      const w = new Workspace()
      const copy = w.duplicate('p0')!.page
      ;(copy.content![0] as { text: string }).text = 'só na cópia'
      copy.tags.push('leitura')
      copy.shares.push({ userId: 'tiago', perms: [] })
      expect((w.page('p0')!.content![0] as { text: string }).text).toBe('O que precisa acontecer antes do dia 31')
      expect(w.page('p0')!.tags).not.toContain('leitura')
      expect(w.page('p0')!.shares).toHaveLength(2)
    })

    it('as imagens não vão para a cópia (o link temporário é do original) e a conta aparece', () => {
      const w = new Workspace()
      w.page('p0')!.content!.push({ id: 'im', type: 'image', name: 'a.png', src: 'blob:a' })
      const made = w.duplicate('p0')!
      expect(made.images).toBe(1)
      expect(made.page.content!.at(-1)).toMatchObject({ type: 'image', src: null, name: null })
      expect(w.page('p0')!.content!.at(-1)).toMatchObject({ src: 'blob:a' })
    })

    it('copiar uma página que recebi cria uma página minha; um título enorme é cortado', () => {
      const w = new Workspace()
      const copy = w.duplicate('s1')!.page
      expect(copy.sharedBy).toBeNull()
      expect(copy.myPerms).toHaveLength(10)
      w.page('p1')!.title = 't'.repeat(120)
      expect(w.duplicate('p1')!.page.title).toHaveLength(120)
      expect(w.duplicate('nao-existe')).toBeNull()
    })
  })
})

describe('Workspace — arquivos de páginas apagadas de vez', () => {
  const file = (fileId: string, id = fileId): Block => ({ id, type: 'file', fileId, name: fileId, size: 1, mime: '', level: 3 })
  const setup = () => {
    const w = new Workspace()
    const gone: string[][] = []
    w.filesGone = (ids) => gone.push(ids)
    return { w, gone }
  }

  it('apagar a página de vez solta os arquivos que só ela usava', () => {
    const { w, gone } = setup()
    w.contentOf('p5')
    w.page('p5')!.content = [file('a'), file('b'), { id: 'img', type: 'image', name: 'x', src: null, fileId: 'c' }]
    w.deleteForever('p5')
    expect(gone).toEqual([['a', 'b', 'c']])
  })

  it('um arquivo que outra página ainda usa fica', () => {
    const { w, gone } = setup()
    w.contentOf('p5')
    w.contentOf('p0')
    w.page('p5')!.content = [file('a'), file('b')]
    w.page('p0')!.content!.push(file('b', 'outro'))
    w.deleteForever('p5')
    expect(gone).toEqual([['a']])
  })

  it('esvaziar a lixeira solta os arquivos de todas as páginas que saem', () => {
    const { w, gone } = setup()
    w.contentOf('p5')
    w.contentOf('p0')
    w.page('p5')!.content = [file('a')]
    w.page('p0')!.content!.push(file('b'))
    w.trash('p5')
    w.trash('p0')
    w.emptyTrash()
    expect(gone).toHaveLength(1)
    expect(gone[0].sort()).toEqual(['a', 'b'])
  })

  it('páginas sem arquivos, ou ainda nunca abertas, não chamam ninguém', () => {
    const { w, gone } = setup()
    w.deleteForever('p5')
    w.trash('p0')
    w.emptyTrash()
    expect(gone).toEqual([])
  })

  it('a página que outra pessoa compartilhou comigo não leva os arquivos dela embora', () => {
    const { w, gone } = setup()
    const shared = w.pages.find((p) => p.sharedBy)!
    w.contentOf(shared.id)
    shared.content = [file('alheio')]
    w.deleteForever(shared.id)
    expect(gone).toEqual([])
  })

  it('apagar uma página que não existe não faz nada', () => {
    const { w, gone } = setup()
    w.deleteForever('nada')
    expect(gone).toEqual([])
    expect(w.pages.length).toBeGreaterThan(0)
  })
})

