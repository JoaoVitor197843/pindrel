import { beforeEach, describe, expect, it } from 'vitest'
import { Nav, noteIdFrom } from './nav.svelte'

describe('noteIdFrom', () => {
  it('lê só /notes/:id de um segmento', () => {
    expect(noteIdFrom('/notes/p0')).toBe('p0')
    expect(noteIdFrom('/notes/abc-DEF_9/')).toBe('abc-DEF_9')
    for (const bad of ['/', '/login', '/notes', '/notes/', '/notes/a/b', '/notes/a b', '/notes/%2e%2e', '/notes/<script>', '/x/notes/a', `/notes/${'a'.repeat(65)}`]) {
      expect(noteIdFrom(bad)).toBeNull()
    }
  })
})

describe('Nav', () => {
  beforeEach(() => history.replaceState(null, '', '/?tela=painel'))

  it('abre uma página mantendo a query e volta pelo histórico', async () => {
    const nav = new Nav()
    expect(nav.noteId).toBeNull()
    nav.open('p0')
    expect(location.pathname).toBe('/notes/p0')
    expect(location.search).toBe('?tela=painel')
    expect(nav.noteId).toBe('p0')
    nav.back()
    await new Promise((r) => setTimeout(r, 30))
    expect(location.pathname).toBe('/')
    expect(nav.noteId).toBeNull()
  })

  it('o botão voltar do navegador também atualiza a tela', async () => {
    const nav = new Nav()
    nav.open('p1')
    nav.open('p2')
    history.back()
    await new Promise((r) => setTimeout(r, 30))
    expect(nav.noteId).toBe('p1')
  })

  it('id inválido não navega', () => {
    const nav = new Nav()
    nav.open('../x')
    nav.open('a/b')
    nav.open('')
    expect(nav.noteId).toBeNull()
    expect(location.pathname).toBe('/')
  })

  it('"voltar" numa página aberta direto pelo endereço vai para o painel', () => {
    history.replaceState(null, '', '/notes/p9?tela=painel')
    const nav = new Nav()
    expect(nav.noteId).toBe('p9')
    nav.back()
    expect(nav.noteId).toBeNull()
    expect(location.pathname).toBe('/')
  })
})
