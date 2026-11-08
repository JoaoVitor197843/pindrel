import { describe, expect, it } from 'vitest'
import { ME, initialsOf, searchUsers, seedUsers } from './users'

const users = seedUsers()
const ids = (q: string) => searchUsers(users, q).map((u) => u.id)

describe('users', () => {
  it('sem busca lista todos; busca por e-mail, username e nome, sem caixa nem acento', () => {
    expect(ids('')).toHaveLength(users.length)
    expect(ids('   ')).toHaveLength(users.length)
    expect(ids('beatriz.lima@familia')).toEqual(['bea'])
    expect(ids('FAMILIA.CASA').sort()).toEqual(['bea', 'helena'])
    expect(ids('tiagof')).toEqual(['tiago'])
    expect(ids('julia')).toEqual(['julia'])
    expect(ids('Júlia')).toEqual(['julia'])
    expect(ids('otavio')).toEqual(['otavio'])
  })

  it('aceita o @ na frente do username', () => {
    expect(ids('@caio')).toEqual(['caio'])
    expect(ids('@')).toHaveLength(users.length)
  })

  it('o que não existe não acha ninguém, e texto estranho não quebra', () => {
    expect(ids('zzzz')).toEqual([])
    for (const weird of ['.*', '(', '[a-', '\\', '<script>', '💥', 'a'.repeat(5000)]) expect(() => searchUsers(users, weird)).not.toThrow()
  })

  it('o diretório tem o próprio usuário e ids únicos, e-mails únicos', () => {
    expect(users.some((u) => u.id === ME)).toBe(true)
    expect(new Set(users.map((u) => u.id)).size).toBe(users.length)
    expect(new Set(users.map((u) => u.email)).size).toBe(users.length)
    expect(new Set(users.map((u) => u.username)).size).toBe(users.length)
  })

  it('iniciais', () => {
    expect(initialsOf('Marina Reis')).toBe('MR')
    expect(initialsOf('  ana  ')).toBe('A')
    expect(initialsOf('')).toBe('?')
    expect(initialsOf('a b c d')).toBe('AB')
  })
})
