import { fold } from './text'

export interface User {
  id: string
  name: string
  username: string
  email: string
}

/** The person using the app: pages without `sharedBy` are theirs. */
export const ME = 'me'


/** Everyone whose e-mail, username or name contains `query` (ignoring case and accents); an empty query lists all. */
export function searchUsers(users: readonly User[], query: string): User[] {
  const q = fold(query.trim().replace(/^@/, ''))
  if (!q) return [...users]
  return users.filter((u) => fold(u.email).includes(q) || fold(u.username).includes(q) || fold(u.name).includes(q))
}

export function initialsOf(name: string): string {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0]!.toUpperCase())
      .join('') || '?'
  )
}
