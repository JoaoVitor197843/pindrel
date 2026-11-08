// Load-test data for the memory measurements (`yarn build --mode loadtest`, see scripts/memory.mjs). It is only reached
// from a branch that is dead in a normal build, so none of it is shipped.
import type { Block } from './stores/blocks'
import { session } from './stores/files.svelte'
import type { Workspace } from './stores/workspace.svelte'

const WORDS = 'fechamento trimestre conciliação financeira revisão contratos relatório conselho servidor backup página bloco cofre senha tag projeto notas reunião'.split(' ')
const sentence = (seed: number, n = 40) => Array.from({ length: n }, (_, k) => WORDS[(seed * 7 + k * 3) % WORDS.length]).join(' ')

/**
 * One block of every kind, in turn, for `?kinds=mixed`: the page then has titles of three sizes (some with a toggle),
 * both kinds of list at several levels, callouts of every tone, a table of contents, links, page links and media, so the
 * memory measured is that of a real page and not only of paragraphs.
 */
function mixed(i: number, pageIds: string[]): Block {
  const id = `g${i}`
  switch (i % 20) {
    case 0:
      return { id, type: 'heading', text: sentence(i, 4), level: (1 + (i % 3)) as 1 | 2 | 3 }
    case 1:
    case 2:
    case 3:
      return { id, type: 'bullet', text: sentence(i, 12), indent: i % 3 }
    case 4:
    case 5:
    case 6:
      return { id, type: 'numbered', text: sentence(i, 12), indent: (i >> 1) % 3 }
    case 7:
      return { id, type: 'callout', text: sentence(i, 20), tone: (['info', 'success', 'warning', 'danger'] as const)[i % 4] }
    case 8:
      return { id, type: 'heading', text: sentence(i, 4), level: 2, toggle: true, body: sentence(i, 30) }
    case 9:
      return { id, type: 'toc' }
    case 10:
      return { id, type: 'bookmark', url: `https://exemplo.com/${i}`, title: sentence(i, 3) }
    case 11:
      return { id, type: 'pagelink', pageId: pageIds[i % pageIds.length], title: 'Página' }
    case 12:
      return { id, type: 'video', url: `https://exemplo.com/video-${i}.mp4`, title: sentence(i, 3) }
    case 13:
      return { id, type: 'audio', url: `https://exemplo.com/audio-${i}.mp3`, title: sentence(i, 3) }
    case 14:
      return { id, type: 'pdf', url: `https://exemplo.com/doc-${i}.pdf`, title: sentence(i, 3) }
    case 15:
      return { id, type: 'quote', text: sentence(i, 16) }
    case 16:
      return { id, type: 'toggle', text: sentence(i, 5), body: sentence(i, 25) }
    case 17:
      return { id, type: 'file', fileId: `fx${i}`, name: `arquivo-${i}.zip`, size: 1_500_000 + i, mime: 'application/zip', level: 2 }
    case 18:
      return { id, type: 'image', name: `foto-${i}.png`, src: null, fileId: `fx${i}` }
    default:
      return { id, type: 'paragraph', text: `${sentence(i)} **${WORDS[i % WORDS.length]}** e *${WORDS[(i + 3) % WORDS.length]}*` }
  }
}

/**
 * `?token=` signs the page in with an access token, so the file routes can be tried against a real server before the
 * login is connected to the editor. Like the rest of this file it is reachable only from a build in loadtest mode.
 */
export function signInFromAddress(params: URLSearchParams) {
  const token = params.get('token')
  if (token && /^[\w-]+\.[\w-]+\.[\w-]+$/.test(token)) session.token = token
}

/** `?pages=N` makes the list N pages long; `?blocks=M` gives the page p0 M paragraphs (`&kinds=mixed`: every kind of block). */
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
    const pageIds = ws.pages.filter((p) => !p.locked && !p.trashed && p.id !== 'p0').map((p) => p.id)
    const kinds = params.get('kinds') === 'mixed'
    for (let i = 0; i < blocks; i++) content?.push(kinds ? mixed(i, pageIds) : { id: `g${i}`, type: 'paragraph', text: sentence(i) })
  }
}
