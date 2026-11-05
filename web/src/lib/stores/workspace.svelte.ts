import { excerptOf, newId, type Block } from './blocks'
import { ALL_PERMS, normalizePerms, type PermKey } from './permissions'
import { fold } from './text'
import { ME, seedUsers, type User } from './users'

export type View = 'all' | 'shared' | 'vault' | 'trash'
export type Sort = 'recent' | 'az'
export type Layout = 'grid' | 'list'
export type TagColor = 'accent' | 'rust' | 'blue' | 'gold' | 'plum' | 'teal'

export const TAG_COLORS: TagColor[] = ['accent', 'rust', 'blue', 'gold', 'plum', 'teal']

export interface Tag {
  id: string
  name: string
  color: TagColor
}

export interface NotePage {
  id: string
  title: string
  excerpt: string
  tags: string[]
  updated: number
  /** Number of blocks (kept in step with `content` once the page has been opened in the editor). */
  blocks: number
  /** The body; null while a page was never opened (the editor then starts it from the excerpt). */
  content: Block[] | null
  created: number
  /** Who shared it with me; null for my own pages. */
  sharedBy: string | null
  /** What I may do with a page that was shared with me (my own pages allow everything). */
  myPerms: PermKey[]
  /** Who I shared my own page with. */
  shares: Share[]
  /** Lives in the vault: its content is hidden until the vault is unlocked. */
  locked: boolean
  trashed: boolean
  pinned: boolean
  /** One emoji, or '' for none. */
  icon: string
  /** A cover spec (see `cover.ts`), or '' for none. */
  cover: string
}

/** One person a page was shared with, and what they may do with it. */
export interface Share {
  userId: string
  perms: PermKey[]
}

export interface Settings {
  useTrash: boolean
  /** Days a trashed page is kept. */
  retention: number
}

// Seed dates are relative to now so the date groups ("Hoje", "Esta semana"...) always have content to show.
const ago = (days: number, hours = 0) => Date.now() - days * 86_400_000 - hours * 3_600_000

// Prototype data (from the Claude Design mock): the real notes come from IndexedDB / sync later.
const seedTags = (): Tag[] => [
  { id: 'pessoal', name: 'pessoal', color: 'accent' },
  { id: 'trabalho', name: 'trabalho', color: 'rust' },
  { id: 'servidor', name: 'servidor', color: 'blue' },
  { id: 'ideias', name: 'ideias', color: 'gold' },
  { id: 'leitura', name: 'leitura', color: 'plum' },
  { id: 'receitas', name: 'receitas', color: 'teal' },
  { id: 'operacoes', name: 'operações', color: 'blue' },
  { id: 'trimestral', name: 'trimestral', color: 'gold' },
  { id: 'cofre', name: 'cofre', color: 'plum' },
]

const closingRoutine = (): Block[] => [
  { id: 'r1', type: 'heading', text: 'O que precisa acontecer antes do dia 31' },
  {
    id: 'r2',
    type: 'paragraph',
    text: 'O fechamento tem três frentes que costumam colidir na última semana: conciliação financeira, revisão dos contratos que renovam em abril e o export dos relatórios para o conselho. A ordem abaixo assume que o time de dados entrega o dump na segunda.',
  },
  {
    id: 'r3',
    type: 'checklist',
    items: [
      { id: 'i1', text: 'Fechar conciliação dos lançamentos de março', done: true },
      { id: 'i2', text: 'Revisar as 4 renovações de contrato com o jurídico', done: true },
      { id: 'i3', text: 'Rodar o export do relatório do conselho', done: false },
      { id: 'i4', text: 'Arquivar as páginas do trimestre anterior', done: false },
    ],
  },
  {
    id: 'r4',
    type: 'code',
    lang: 'python',
    text: '# rotina noturna: sela o que já está conciliado\ndef selar_trimestre(paginas, chave):\n    seladas = []\n    for pagina in paginas:\n        if pagina.status == "conciliada":\n            pagina.corpo = cifrar(pagina.corpo, chave)\n            seladas.append(pagina.id)\n    return {"ok": True, "total": len(seladas)}',
  },
  {
    id: 'r5',
    type: 'spoiler',
    text: 'O conselho vai pedir o corte de 12% no orçamento de infra antes de aprovar o plano de abril — chegue com o cenário B pronto e não abra o número de headcount na primeira rodada.',
  },
  { id: 'r6', type: 'secure', text: 'Chave do cofre trimestral: PNDR-4471-QF29-TRIM — válida até 05 abr, gira automaticamente depois do fechamento.' },
  {
    id: 'r7',
    type: 'table',
    cols: [
      { id: 'c1', label: 'Frente', w: 250 },
      { id: 'c2', label: 'Responsável', w: 170 },
      { id: 'c3', label: 'Prazo', w: 120 },
    ],
    rows: [
      { c1: 'Conciliação', c2: 'Marina', c3: '24 mar' },
      { c1: 'Contratos', c2: 'Jurídico', c3: '27 mar' },
      { c1: 'Relatório do conselho', c2: 'Ruy', c3: '31 mar' },
    ],
  },
]

type Seed = [id: string, title: string, excerpt: string, tags: string[], updated: number, blocks: number, extra?: Partial<NotePage>]

const seedPages = (): NotePage[] =>
  (
    [
      ['p1', 'Reforma do apartamento — orçamento', 'Pedreiro confirmou para segunda. Falta decidir o piso da sala: vinílico ou taco recuperado. Orçamento total até agora R$ 18.400.', ['pessoal'], ago(0), 4],
      ['p0', 'Rotina de encerramento do trimestre', 'O fechamento tem três frentes que costumam colidir na última semana: conciliação financeira, revisão dos contratos que renovam em abril e o export dos relatórios para o conselho.', ['operacoes', 'trimestral', 'cofre'], ago(1, 2), 7, { created: ago(40), icon: '📋', cover: 'musgo', content: closingRoutine(), shares: [{ userId: 'caio', perms: [...ALL_PERMS] }, { userId: 'julia', perms: [] }] }],
      ['p2', 'Migração do servidor para NixOS', 'Passos: exportar volumes do Docker, escrever configuration.nix, testar em VM antes de tocar no bare metal. Backup do Postgres primeiro.', ['servidor', 'trabalho'], ago(1), 11, { icon: '🛠️', cover: 'oceano', pinned: true, shares: [{ userId: 'rafa', perms: ['text', 'checklist', 'export'] }] }],
      ['p3', 'Notas da reunião de produto', 'Roadmap do trimestre ficou em três frentes. A equipe de suporte pediu prioridade para o histórico de edições — parece justo.', ['trabalho', 'trimestral'], ago(1, 5), 7],
      ['p4', 'Senhas e chaves de recuperação', 'root@nas · 2FA de emergência · seed de 24 palavras', ['pessoal'], ago(2), 1, { locked: true }],
      ['p5', 'Pão de fermentação natural', 'Levain 20%, hidratação 72%, sal 2%. Autólise de 40 minutos e três dobras a cada 30. Forno a 250 °C com vapor nos primeiros 20.', ['receitas'], ago(3), 3, { icon: '🍽️' }],
      ['p6', 'Ideias para o Pindrel', 'Backlinks entre páginas. Modo leitura sem sidebar. Exportar tudo como markdown num zip. Atalho para busca global em qualquer tela.', ['ideias', 'trabalho'], ago(5), 9, { icon: '💡', pinned: true }],
      ['p7', 'Lista de leitura 2025', 'Terminei "A Cidade e a Cidade". Próximos: Solaris, Cem Anos de Solidão (releitura) e o livro de ensaios que a Júlia emprestou.', ['leitura'], ago(7), 18],
      ['p8', 'Rotina de backup — checklist', 'restic para o NAS toda madrugada, cópia semanal criptografada fora de casa. Testar restauração no primeiro domingo do mês.', ['servidor', 'pessoal', 'operacoes'], ago(8), 6],
      ['p9', 'Viagem ao Vale do Capão', 'Quatro dias em abril. Pousada reservada, falta acertar carona da rodoviária. Levar lanterna, filtro de água e capa de chuva.', ['pessoal'], ago(10), 5, { icon: '✈️', cover: 'areia' }],
      ['p10', 'Estudo: por que Fraunces funciona', 'Serifas com eixo levemente inclinado dão calor sem parecer nostálgico. Em títulos curtos ganha personalidade; em corpo, cansa.', ['ideias', 'leitura'], ago(13), 8],
      ['p11', 'Cardápio da semana', 'Segunda: grão-de-bico. Terça: sopa de abóbora. Quarta: sobra criativa. Quinta: macarrão de alho. Sexta: pizza, sempre pizza.', ['receitas', 'pessoal'], ago(14), 2],
      ['p12', 'Contrato do freelance — cláusulas', 'Escopo fechado com duas rodadas de revisão. Pagamento 40/60. Adicionar cláusula de reajuste se o prazo passar de 8 semanas.', ['trabalho', 'operacoes'], ago(17), 12],
      ['p13', 'Configuração do Caddy + Tailscale', 'Reverse proxy só na tailnet, sem porta aberta pra internet. Certificado interno resolvido pelo próprio Caddy. Anotar o IP do MagicDNS.', ['servidor'], ago(20), 10],
      ['p14', 'Perguntas para a consulta', 'Levar exames de janeiro. Perguntar sobre a dose e se dá para espaçar o retorno para seis meses.', ['pessoal'], ago(22), 3],
      ['p15', 'Glossário do projeto', 'Página = documento. Bloco = unidade editável. Cofre = coleção com criptografia local. Evitar "workspace", ninguém usa isso aqui.', ['trabalho', 'ideias'], ago(24), 15],
      ['p16', 'Sementes da horta de inverno', 'Rúcula e coentro direto na terra. Tomate cereja em bandeja, transplantar em três semanas. A manjericona do ano passado voltou sozinha.', ['pessoal', 'receitas'], ago(27), 4],
      ['p17', 'Anotações do curso de tipografia', 'Aula 4: entrelinha cresce com a medida da linha, não com o corpo. Exercício: compor a mesma página em três escalas modulares.', ['leitura', 'ideias'], ago(30), 13],
      ['p18', 'Orçamento doméstico — fevereiro', 'Fechou 6% abaixo do mês passado. Mercado continua sendo a maior linha; assinaturas cortadas: duas.', ['pessoal'], ago(33), 6],
      ['v2', 'Chave da API do provedor de IA', 'sk-ant-… (rotacionar em setembro)', ['trabalho'], ago(6), 1, { locked: true }],
      ['v3', 'Documentos — RG, CPF, passaporte', 'passaporte FG882301, validade 2031', ['pessoal'], ago(12), 1, { locked: true }],
      ['v4', 'Cofre do servidor doméstico', 'LUKS header backup + frase de recuperação', ['servidor'], ago(30), 1, { locked: true }],
      ['v5', 'Contas bancárias e PIX', 'agência 0412 · chave PIX por e-mail', ['pessoal'], ago(60), 1, { locked: true }],
      ['s1', 'Retro da sprint 14 (equipe)', 'Três coisas que funcionaram, duas para parar de fazer. Comentários abertos até sexta.', ['trabalho'], ago(0, 4), 0, { sharedBy: 'Caio' }],
      ['s2', 'Plano de mudança — casa nova', 'Divisão de caixas por ambiente e a lista do que doar antes de empacotar.', ['pessoal'], ago(2, 6), 0, { sharedBy: 'Júlia', myPerms: [] }],
      ['s3', 'Runbook de incidentes', 'Quem acionar, em que ordem, e onde ficam os logs de cada serviço do cluster.', ['servidor', 'trabalho'], ago(6), 0, { sharedBy: 'Rafa', myPerms: ['text', 'checklist', 'blocks', 'tables', 'secure', 'export'] }],
    ] as Seed[]
  ).map(([id, title, excerpt, tags, updated, blocks, extra]) => ({
    id,
    title,
    excerpt,
    tags,
    updated,
    blocks,
    content: null,
    created: updated - 3 * 86_400_000,
    sharedBy: null,
    myPerms: [...ALL_PERMS],
    shares: [],
    locked: false,
    trashed: false,
    pinned: false,
    icon: '',
    cover: '',
    ...extra,
  }))

export interface PageGroup {
  key: string
  /** null: no visible heading (a single flat list). */
  label: string | null
  pages: NotePage[]
}

export { fold }

const MAX_TITLE = 120
export const MAX_TAG_NAME = 24
/** The master password only needs this many characters in the prototype (the real one is checked by Argon2id). */
export const MIN_VAULT_PASSWORD = 4

/** The state of the dashboard. One instance per screen, so tests start clean. */
export class Workspace {
  pages = $state<NotePage[]>(seedPages())
  tags = $state<Tag[]>(seedTags())
  users = $state<User[]>(seedUsers())
  settings = $state<Settings>({ useTrash: true, retention: 30 })
  vaultUnlocked = $state(false)
  view = $state<View>('all')
  sort = $state<Sort>('recent')
  layout = $state<Layout>('grid')
  query = $state('')
  tagFilter = $state<string | null>(null)
  #seq = 100

  live = $derived(this.pages.filter((p) => !p.trashed))
  /** My own pages: "all pages" never lists what others shared with me. */
  mine = $derived(this.live.filter((p) => !p.sharedBy))
  counts = $derived({
    all: this.mine.length,
    shared: this.live.length - this.mine.length,
    vault: this.live.filter((p) => p.locked).length,
    trash: this.pages.length - this.live.length,
  })
  tagCounts = $derived(
    Object.fromEntries(this.tags.map((t) => [t.id, this.mine.filter((p) => p.tags.includes(t.id)).length])) as Record<string, number>,
  )

  /** What the current view shows, after search, tag filter and sort. */
  visible = $derived.by(() => {
    if (this.view === 'vault') return []
    const q = fold(this.query.trim())
    const base =
      this.view === 'trash'
        ? this.pages.filter((p) => p.trashed)
        : this.view === 'shared'
          ? this.live.filter((p) => p.sharedBy)
          : this.mine
    const list = base.filter(
      (p) =>
        (!this.tagFilter || p.tags.includes(this.tagFilter)) &&
        (!q || fold(p.title).includes(q) || (this.#readable(p) && fold(p.excerpt).includes(q))),
    )
    return list.sort((a, b) => (this.sort === 'az' ? a.title.localeCompare(b.title, 'pt-BR') : b.updated - a.updated))
  })

  /** The pages that live in the vault. */
  visibleVault = $derived.by(() => {
    const q = fold(this.query.trim())
    // a locked vault matches on titles only: the content is not readable
    return this.live
      .filter((p) => p.locked && (!q || fold(p.title).includes(q) || (this.vaultUnlocked && fold(p.excerpt).includes(q))))
      .sort((a, b) => b.updated - a.updated)
  })

  /** A page's text may be read (searched, shown on a card) unless it is in a vault that is still locked. */
  #readable(p: NotePage) {
    return !p.locked || this.vaultUnlocked
  }

  /**
   * `visible` split into sections: pinned first, then by date (or one list when sorted A–Z). Search results and the
   * trash stay a single flat list, where sections would only hide matches.
   */
  groups = $derived.by((): PageGroup[] => {
    const list = this.visible
    if (this.view === 'trash' || this.query.trim()) return [{ key: 'all', label: null, pages: list }]
    const out: PageGroup[] = []
    const pinned = list.filter((p) => p.pinned)
    const rest = list.filter((p) => !p.pinned)
    if (pinned.length) out.push({ key: 'pinned', label: 'Fixadas', pages: pinned })
    if (this.sort === 'az') {
      if (rest.length) out.push({ key: 'rest', label: pinned.length ? 'Outras' : null, pages: rest })
      return out
    }
    const startOfDay = new Date().setHours(0, 0, 0, 0)
    const buckets: [string, string, number][] = [
      ['today', 'Hoje', startOfDay],
      ['week', 'Esta semana', startOfDay - 6 * 86_400_000],
      ['month', 'Últimos 30 dias', startOfDay - 29 * 86_400_000],
      ['older', 'Mais antigas', -Infinity],
    ]
    let remaining = rest
    for (const [key, label, from] of buckets) {
      const here = remaining.filter((p) => p.updated >= from)
      remaining = remaining.filter((p) => p.updated < from)
      if (here.length) out.push({ key, label, pages: here })
    }
    return out
  })

  tag(id: string) {
    return this.tags.find((t) => t.id === id)
  }

  go(view: View) {
    this.view = view
    this.tagFilter = null
  }

  toggleTagFilter(id: string) {
    this.tagFilter = this.tagFilter === id ? null : id
    // a tag filters my own pages
    if (this.view === 'vault' || this.view === 'shared') this.view = 'all'
  }

  clearFilters() {
    this.query = ''
    this.tagFilter = null
  }

  /** Brings a page into view (the prototype has no editor yet): its view, no tag filter, its title as the search. */
  reveal(id: string) {
    const p = this.pages.find((x) => x.id === id)
    if (!p) return
    this.view = p.trashed ? 'trash' : p.sharedBy ? 'shared' : 'all'
    this.tagFilter = null
    this.query = p.title
  }

  /** Adds an empty page at the top of "all pages" and returns it. */
  newPage(title = 'Sem título'): NotePage {
    const page: NotePage = {
      id: `n${++this.#seq}`,
      title: title.trim().slice(0, MAX_TITLE) || 'Sem título',
      excerpt: '',
      tags: this.tagFilter ? [this.tagFilter] : [],
      updated: Date.now(),
      blocks: 0,
      content: [],
      created: Date.now(),
      sharedBy: null,
      myPerms: [...ALL_PERMS],
      shares: [],
      locked: false,
      trashed: false,
      pinned: false,
      icon: '',
      cover: '',
    }
    this.pages.unshift(page)
    this.view = 'all'
    this.query = ''
    this.sort = 'recent'
    return page
  }

  page(id: string) {
    return this.pages.find((p) => p.id === id)
  }

  /** The body of a page; one that was never opened starts as a single paragraph with its excerpt. */
  contentOf(id: string): Block[] | null {
    const p = this.page(id)
    if (!p) return null
    if (!p.content) p.content = p.excerpt ? [{ id: `${p.id}-b0`, type: 'paragraph', text: p.excerpt }] : []
    return p.content
  }

  /** After an edit: the card shows the new excerpt, block count and time. */
  touch(id: string) {
    const p = this.page(id)
    if (!p) return
    p.updated = Date.now()
    if (p.content) {
      p.blocks = p.content.length
      p.excerpt = excerptOf(p.content)
    }
  }

  /** Other pages that share tags with this one, the ones sharing the most first. Vault pages are never suggested. */
  related(id: string, limit = 5): NotePage[] {
    const page = this.page(id)
    if (!page || page.tags.length === 0) return []
    const overlap = (p: NotePage) => p.tags.filter((t) => page.tags.includes(t)).length
    return this.live
      .filter((p) => p.id !== id && !p.locked && overlap(p) > 0)
      .sort((a, b) => overlap(b) - overlap(a) || b.updated - a.updated)
      .slice(0, limit)
  }

  /**
   * A copy of the page that belongs to me: same body and tags, no sharing, not pinned. Images are left out (their
   * temporary links belong to the original); returns the copy and how many images stayed behind.
   */
  duplicate(id: string): { page: NotePage; images: number } | null {
    const src = this.page(id)
    if (!src) return null
    const body: Block[] = JSON.parse(JSON.stringify(this.contentOf(id) ?? []))
    let images = 0
    for (const b of body) {
      b.id = newId()
      if (b.type === 'image' && b.src) {
        images++
        b.src = null
        b.name = null
      }
    }
    const now = Date.now()
    const copy: NotePage = {
      ...JSON.parse(JSON.stringify({ ...src, content: null })),
      id: `n${++this.#seq}`,
      title: `${src.title} (cópia)`.slice(0, MAX_TITLE),
      content: body,
      blocks: body.length,
      created: now,
      updated: now,
      sharedBy: null,
      myPerms: [...ALL_PERMS],
      shares: [],
      pinned: false,
      trashed: false,
    }
    this.pages.unshift(copy)
    return { page: this.page(copy.id)!, images }
  }

  togglePin(id: string) {
    const p = this.pages.find((x) => x.id === id)
    if (p) p.pinned = !p.pinned
  }

  /** Moves a page to the trash, or deletes it for good when the trash is turned off in the settings. */
  trash(id: string) {
    // vault pages never wait in the trash; a trash that is turned off deletes at once too
    if (!this.settings.useTrash || this.page(id)?.locked) {
      this.pages = this.pages.filter((p) => p.id !== id)
      return
    }
    const p = this.pages.find((x) => x.id === id)
    if (p) p.trashed = true
  }

  restore(id: string) {
    const p = this.pages.find((x) => x.id === id)
    if (p) p.trashed = false
  }

  emptyTrash() {
    this.pages = this.pages.filter((p) => !p.trashed)
  }

  /** Returns the new tag, or the existing one when the name is already taken; null for an empty name. */
  addTag(name: string, color: TagColor = 'accent'): Tag | null {
    const clean = name.trim().replace(/\s+/g, '-').slice(0, MAX_TAG_NAME)
    if (!clean) return null
    const id = fold(clean)
    const existing = this.tags.find((t) => t.id === id)
    if (existing) return existing
    const tag: Tag = { id, name: clean.toLowerCase(), color: TAG_COLORS.includes(color) ? color : 'accent' }
    this.tags.push(tag)
    return tag
  }

  /** Prototype: any password of at least MIN_VAULT_PASSWORD characters opens it; nothing is decrypted yet. */
  unlockVault(password: string): 'ok' | 'short' {
    if (password.trim().length < MIN_VAULT_PASSWORD) return 'short'
    this.vaultUnlocked = true
    return 'ok'
  }

  lockVault() {
    this.vaultUnlocked = false
  }

  deleteForever(id: string) {
    this.pages = this.pages.filter((p) => p.id !== id)
  }

  /** A new, empty vault page. Only while the vault is unlocked. */
  addVaultEntry(): NotePage | null {
    if (!this.vaultUnlocked) return null
    const page = this.newPage('Nova entrada segura')
    page.locked = true
    // the vault is where it lives: stay there
    this.view = 'vault'
    return page
  }

  user(id: string) {
    return this.users.find((u) => u.id === id)
  }

  /** Gives these people access; unknown people, myself and people who already have it are skipped. */
  sharePage(id: string, userIds: string[], perms: PermKey[]): number {
    const p = this.page(id)
    if (!p) return 0
    const clean = normalizePerms(perms)
    let added = 0
    for (const userId of new Set(userIds)) {
      if (userId === ME || !this.user(userId) || p.shares.some((s) => s.userId === userId)) continue
      p.shares.push({ userId, perms: [...clean] })
      added++
    }
    return added
  }

  setShare(id: string, userId: string, perms: PermKey[]) {
    const share = this.page(id)?.shares.find((s) => s.userId === userId)
    if (share) share.perms = normalizePerms(perms)
  }

  unshare(id: string, userId: string) {
    const p = this.page(id)
    if (p) p.shares = p.shares.filter((s) => s.userId !== userId)
  }

  unshareAll(id: string) {
    const p = this.page(id)
    if (p) p.shares = []
  }

  saveSettings(next: Settings) {
    this.settings = { useTrash: next.useTrash, retention: Math.min(90, Math.max(7, Math.round(next.retention) || 30)) }
  }
}

const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

export function formatDate(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getDate()).padStart(2, '0')} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`
}

/** The small right-hand note of a card: where it lives, who shared it, or its size. */
export function pageMeta(p: NotePage): string {
  if (p.locked) return 'cofre'
  if (p.sharedBy) return `por ${p.sharedBy}`
  return `${p.blocks} ${p.blocks === 1 ? 'bloco' : 'blocos'}`
}
