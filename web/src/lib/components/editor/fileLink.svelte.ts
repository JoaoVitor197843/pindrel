import type { PageEditor } from '../../stores/editor.svelte'

/**
 * The address to read one file of the server, for as long as the block is drawn. It asks when the block appears, once, and
 * hands out a new one on request (`refresh`) when the old one stopped working: a player or an image asks again by itself
 * after an error; nothing renews it in the background, so a page left open costs no requests.
 */
export function fileLink(editor: () => PageEditor, id: () => string | undefined) {
  let url = $state('')
  let error = $state('')
  let busy = false

  async function load(fresh: boolean): Promise<string> {
    const fileId = id()
    if (!fileId) return ''
    busy = true
    try {
      const next = await editor().files.url(fileId, fresh)
      if (id() === fileId) {
        url = next
        error = ''
      }
      return next
    } catch {
      error = 'Não foi possível abrir o arquivo'
      return ''
    } finally {
      busy = false
    }
  }

  $effect(() => {
    const fileId = id()
    url = ''
    error = ''
    if (fileId && editor().files.available) void load(false)
  })

  return {
    get url() {
      return url
    },
    get error() {
      return error
    },
    get busy() {
      return busy
    },
    /** A new address, replacing the current one. */
    refresh: () => load(true),
  }
}
