// Sample notes, tags and people. The product starts empty; this exists for tests and for the memory measurements
// (`yarn memory`, a build in loadtest mode), and nothing in the normal bundle imports it.
import type { Block } from './stores/blocks'
import { ALL_PERMS } from './stores/permissions'
import { ME, type User } from './stores/users'
import { Workspace, type NotePage, type Tag } from './stores/workspace.svelte'

export const seedUsers = (): User[] => [
  { id: ME, name: 'Marina Reis', username: 'marina', email: 'marina@pindrel.local' },
  { id: 'caio', name: 'Caio Mendes', username: 'caio', email: 'caio@pindrel.local' },
  { id: 'julia', name: 'Júlia Prado', username: 'julia', email: 'julia@pindrel.local' },
  { id: 'rafa', name: 'Rafael Souza', username: 'rafa', email: 'rafa@pindrel.local' },
  { id: 'ruy', name: 'Ruy Almeida', username: 'ruy', email: 'ruy@pindrel.local' },
  { id: 'bea', name: 'Beatriz Lima', username: 'bealima', email: 'beatriz.lima@familia.casa' },
  { id: 'tiago', name: 'Tiago Ferraz', username: 'tiagof', email: 'tiago@pindrel.local' },
  { id: 'helena', name: 'Helena Costa', username: 'helena', email: 'helena@familia.casa' },
  { id: 'otavio', name: 'Otávio Nunes', username: 'otavio', email: 'otavio@pindrel.local' },
]

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

/** Fills a workspace with the sample notes, tags and people. */
export function fillSample(ws: Workspace): Workspace {
  ws.pages = seedPages()
  ws.tags = seedTags()
  ws.users = seedUsers()
  return ws
}

/** A workspace that already holds the sample data. */
export const sampleWorkspace = () => fillSample(new Workspace())
