// What a person who was given a page may do with it. The owner may do everything.

export const PERMS = [
  { key: 'text', label: 'Editar textos e títulos', hint: 'Parágrafos, títulos, itens, código e células de tabela' },
  { key: 'checklist', label: 'Marcar itens de checklist', hint: 'Só marcar e desmarcar, sem mudar o texto' },
  { key: 'blocks', label: 'Adicionar, remover e reordenar blocos', hint: 'Inclui criar e apagar itens de uma checklist' },
  { key: 'tables', label: 'Alterar linhas e colunas de tabelas', hint: 'Adicionar, remover, mover e redimensionar' },
  { key: 'images', label: 'Adicionar imagens', hint: 'Colocar ou trocar imagens nos blocos de imagem' },
  { key: 'tags', label: 'Adicionar e remover tags', hint: 'As tags da página' },
  { key: 'secure', label: 'Ver blocos seguros', hint: 'Ainda pede a senha mestra de quem está vendo' },
  { key: 'share', label: 'Compartilhar com outras pessoas', hint: 'Só adicionar: retirar acesso é de quem criou a página' },
  { key: 'export', label: 'Exportar a página', hint: 'Markdown, HTML, texto e JSON' },
  { key: 'delete', label: 'Excluir a página', hint: 'Para quem a recebeu, só some da sua lista' },
] as const

export type PermKey = (typeof PERMS)[number]['key']
export const ALL_PERMS: PermKey[] = PERMS.map((p) => p.key)

export type AccessLevel = 'edit' | 'read' | 'custom'

export const LEVEL_LABEL: Record<AccessLevel, string> = {
  edit: 'Editar tudo',
  read: 'Somente leitura',
  custom: 'Personalizado',
}

/** Everything allowed is "edit"; nothing allowed is "read"; anything between is custom. */
export function levelOf(perms: readonly PermKey[]): AccessLevel {
  const set = new Set(perms)
  if (ALL_PERMS.every((k) => set.has(k))) return 'edit'
  return ALL_PERMS.some((k) => set.has(k)) ? 'custom' : 'read'
}

export const permsFor = (level: Exclude<AccessLevel, 'custom'>): PermKey[] => (level === 'edit' ? [...ALL_PERMS] : [])

/** Keeps only known permissions, once each, in the canonical order: whatever comes in (storage, a form) is safe. */
export function normalizePerms(input: unknown): PermKey[] {
  if (!Array.isArray(input)) return []
  const set = new Set(input)
  return ALL_PERMS.filter((k) => set.has(k))
}

/** "Editar tudo", "Somente leitura", or "Personalizado (6 de 10)". */
export function describePerms(perms: readonly PermKey[]): string {
  const level = levelOf(perms)
  return level === 'custom' ? `${LEVEL_LABEL.custom} (${perms.length} de ${ALL_PERMS.length})` : LEVEL_LABEL[level]
}
