import { fold } from './text'

export interface User {
  id: string
  name: string
  username: string
  email: string
}

/** The person using the app: pages without `sharedBy` are theirs. */
export const ME = 'me'

// Prototype directory: the real one comes from the server (every account of this instance).
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
