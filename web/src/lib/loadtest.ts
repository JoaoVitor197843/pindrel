// Load-test data for the memory measurements (`yarn build --mode loadtest`, see scripts/memory.mjs). It is only reached
// from a branch that is dead in a normal build, so none of it is shipped.
import type { Workspace } from './stores/workspace.svelte'

const WORDS = 'fechamento trimestre conciliação financeira revisão contratos relatório conselho servidor backup página bloco cofre senha tag projeto notas reunião'.split(' ')
const sentence = (seed: number, n = 40) => Array.from({ length: n }, (_, k) => WORDS[(seed * 7 + k * 3) % WORDS.length]).join(' ')

/** `?pages=N` makes the list N pages long; `?blocks=M` gives the page p0 M paragraphs. */
export function seedLoad(ws: Workspace, params: URLSearchParams) {
  const pages = Number(params.get('pages') ?? 0)
  const blocks = Number(params.get('blocks') ?? 0)
  const tags = ws.tags.map((t) => t.id)
  if (Number.isInteger(pages) && pages > ws.pages.length) {
    const now = Date.now()
    const template = JSON.parse(JSON.stringify(ws.pages.find((p) => !p.locked && !p.sharedBy) ?? ws.pages[0]))
    for (let i = ws.pages.length; i < pages; i++) {
      ws.pages.push({
        ...template,
        id: `L${i}`,
        title: `Página de carga ${i} — ${sentence(i, 3)}`,
        excerpt: sentence(i, 28),
        tags: [...new Set([tags[i % tags.length], tags[(i * 3 + 1) % tags.length]])],
        updated: now - i * 3_600_000,
        created: now - i * 3_700_000,
        content: null,
        blocks: 5,
        pinned: false,
        shares: [],
        icon: '',
        cover: '',
      })
    }
  }
  if (Number.isInteger(blocks) && blocks > 0) {
    ws.contentOf('p0')
    const content = ws.page('p0')?.content
    for (let i = 0; i < blocks; i++) content?.push({ id: `g${i}`, type: 'paragraph', text: sentence(i) })
  }
}
