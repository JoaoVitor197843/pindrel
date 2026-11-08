const NOTE_PATH = /^\/notes\/([A-Za-z0-9_-]{1,64})\/?$/

/** The page id in a `/notes/:id` path, or null for any other path (the same shape the server lets through). */
export function noteIdFrom(pathname: string): string | null {
  return NOTE_PATH.exec(pathname)?.[1] ?? null
}

/** Minimal router: the dashboard at `/…` and one page at `/notes/:id`, kept in the browser's history. */
export class Nav {
  noteId = $state<string | null>(noteIdFrom(location.pathname))
  #pushed = false

  constructor() {
    window.addEventListener('popstate', () => {
      this.noteId = noteIdFrom(location.pathname)
    })
  }

  open(id: string) {
    if (!noteIdFrom(`/notes/${id}`)) return
    history.pushState(null, '', `/notes/${id}${location.search}`)
    this.#pushed = true
    this.noteId = id
  }

  back() {
    if (this.#pushed) {
      this.#pushed = false
      history.back() // popstate brings the dashboard back
    } else {
      history.pushState(null, '', `/${location.search}`)
      this.noteId = null
    }
  }
}
