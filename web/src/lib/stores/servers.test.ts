import { beforeEach, describe, expect, it } from 'vitest'
import { selection, servers } from './servers.svelte'

beforeEach(() => selection.select(servers[0]))

describe('servers', () => {
  it('o servidor embutido é o primeiro, o padrão, e aponta para quem serve a página', () => {
    expect(servers[0].id).toBe('embedded')
    expect(servers[0].address).toBe(window.location.host)
    expect(selection.selected.id).toBe(servers[0].id)
  })

  it('ids são únicos (usados como chave do {#each})', () => {
    const ids = servers.map((s) => s.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it('select troca o servidor e pode voltar ao embutido', () => {
    selection.select(servers[1])
    expect(selection.selected.id).toBe(servers[1].id)
    selection.select(servers[0])
    expect(selection.selected.id).toBe('embedded')
  })

  it('selecionar o mesmo servidor várias vezes é inofensivo', () => {
    for (let i = 0; i < 50; i++) selection.select(servers[1])
    expect(selection.selected.id).toBe(servers[1].id)
  })
})
