import { fold, formatDate, type Workspace } from '../../stores/workspace.svelte'
import { canVault } from '../../capabilities'
import type { IconName } from './Icon.svelte'

export interface PaletteItem {
  label: string
  meta: string
  icon?: IconName
  /** Tag id whose color dot replaces the icon. */
  dot?: string
  run: () => void
}

export interface PaletteGroup {
  label: string
  items: PaletteItem[]
}

export interface PaletteActions {
  newPage: () => void
  openSettings: () => void
  close: () => void
  /** Opens a page in the editor; without it, picking a page only brings it into view in the list. */
  open?: (id: string) => void
}

/** What the command palette lists for `query`: pages, actions and tags, in that order, empty groups left out. */
export function buildPalette(ws: Workspace, query: string, act: PaletteActions): PaletteGroup[] {
  const q = fold(query.trim())
  const match = (s: string) => !q || fold(s).includes(q)

  const pages: PaletteItem[] = ws.live
    .filter((p) => match(p.locked && !ws.vaultUnlocked ? p.title : `${p.title} ${p.excerpt}`))
    .sort((a, b) => b.updated - a.updated)
    .slice(0, 6)
    .map((p) => ({
      label: p.title,
      meta: formatDate(p.updated),
      icon: p.locked ? 'lock' : 'page',
      run: () => {
        if (act.open) act.open(p.id)
        else {
          ws.reveal(p.id)
          act.close()
        }
      },
    }))

  const actions: PaletteItem[] = [
    { label: 'Criar nova página', meta: 'n', icon: 'plus', run: act.newPage },
    { label: 'Abrir configurações', meta: 'conf', icon: 'gear', run: act.openSettings },
    ...(canVault()
      ? [
          {
            label: 'Ir para o cofre',
            meta: 'cofre',
            icon: 'lock' as const,
            run: () => {
              ws.go('vault')
              act.close()
            },
          },
        ]
      : []),
    {
      label: 'Ver lixeira',
      meta: 'lixeira',
      icon: 'trash',
      run: () => {
        ws.go('trash')
        act.close()
      },
    },
    {
      label: 'Alternar ordenação',
      meta: ws.sort === 'recent' ? 'A–Z' : 'recentes',
      icon: 'sort',
      run: () => {
        ws.sort = ws.sort === 'recent' ? 'az' : 'recent'
        act.close()
      },
    },
  ].filter((a) => match(a.label)) as PaletteItem[]

  const tags: PaletteItem[] = ws.tags
    .filter((t) => match(t.name))
    .map((t) => ({
      label: `#${t.name}`,
      meta: `${ws.tagCounts[t.id] ?? 0} págs`,
      dot: t.id,
      run: () => {
        ws.view = 'all'
        ws.tagFilter = t.id
        act.close()
      },
    }))

  return [
    { label: 'Páginas', items: pages },
    { label: 'Ações', items: actions },
    { label: 'Tags', items: tags },
  ].filter((g) => g.items.length)
}
