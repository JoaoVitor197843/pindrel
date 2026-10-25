/**
 * Which server was behind each name the last time the user opened it. An announcement is anonymous, so anyone on the
 * network can call themselves "Casa"; the id the real server keeps is what lets us notice that the one answering now is
 * not the one opened before. Kept in the browser only, never sent anywhere.
 */
const KEY = 'plany:servers'
const MAX_REMEMBERED = 64

export type Trust = 'new' | 'same' | 'changed'

/** Oldest first, so the oldest goes when the list is full. */
type Entries = [name: string, id: string][]

function read(): Entries {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(KEY) ?? '[]')
    if (!Array.isArray(parsed)) return []
    return parsed
      .filter((e): e is [string, string] => Array.isArray(e) && typeof e[0] === 'string' && typeof e[1] === 'string')
      .slice(-MAX_REMEMBERED)
  } catch {
    return []
  }
}

function write(entries: Entries) {
  try {
    localStorage.setItem(KEY, JSON.stringify(entries))
  } catch {
    // no storage (private window, blocked, full): nothing is remembered and nobody is warned, which is how it was
  }
}

/**
 * `new`: never opened (or opened when it had no id). `same`: the id it had. `changed`: another id under the same
 * name, or no id where there was one (a server does not lose its id; an imitation of it never had it).
 */
export function trustOf(name: string, id: string): Trust {
  const known = read().find(([n]) => n === name)
  if (!known || known[1] === '') return known && id === '' ? 'same' : 'new'
  return known[1] === id ? 'same' : 'changed'
}

export function remember(name: string, id: string) {
  const entries = read().filter(([n]) => n !== name)
  entries.push([name, id])
  write(entries.slice(-MAX_REMEMBERED))
}
