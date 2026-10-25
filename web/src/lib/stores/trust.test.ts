import { beforeEach, describe, expect, it, vi } from 'vitest'
import { stubLocalStorage } from '../../test/storage'
import { remember, trustOf } from './trust'

let data: Map<string, string>
beforeEach(() => {
  data = stubLocalStorage()
})
describe('trust', () => {
  it('um nome nunca aberto é novo', () => {
    expect(trustOf('Casa', 'abc')).toBe('new')
    expect(trustOf('Casa', '')).toBe('new')
  })

  it('o mesmo id sob o mesmo nome é o mesmo servidor', () => {
    remember('Casa', 'abc')
    expect(trustOf('Casa', 'abc')).toBe('same')
  })

  it('outro id sob o mesmo nome mudou, e sem id onde havia também', () => {
    remember('Casa', 'abc')
    expect(trustOf('Casa', 'xyz')).toBe('changed')
    expect(trustOf('Casa', '')).toBe('changed')
  })

  it('outro nome com outro id não é mudança', () => {
    remember('Casa', 'abc')
    expect(trustOf('Escritório', 'xyz')).toBe('new')
  })

  it('servidor que não tinha id e passa a ter não é aviso; sem id e continuando sem id é o mesmo', () => {
    remember('Velho', '')
    expect(trustOf('Velho', 'abc')).toBe('new')
    expect(trustOf('Velho', '')).toBe('same')
  })

  it('lembrar de novo troca o id (o usuário confirmou)', () => {
    remember('Casa', 'abc')
    remember('Casa', 'xyz')
    expect(trustOf('Casa', 'xyz')).toBe('same')
    expect(trustOf('Casa', 'abc')).toBe('changed')
    expect(JSON.parse(data.get('plany:servers')!)).toHaveLength(1)
  })

  it('guarda no máximo 64 nomes e esquece o mais antigo', () => {
    for (let i = 0; i < 100; i++) remember(`S${i}`, `id${i}`)
    expect(JSON.parse(data.get('plany:servers')!)).toHaveLength(64)
    expect(trustOf('S99', 'id99')).toBe('same')
    expect(trustOf('S0', 'qualquer')).toBe('new')
  })

  it('nomes estranhos não quebram nada (nem __proto__)', () => {
    for (const name of ['__proto__', 'constructor', '', ' ', '😀'.repeat(40), 'a"b\\n']) {
      remember(name, 'id1')
      expect(trustOf(name, 'id1')).toBe('same')
      expect(trustOf(name, 'id2')).toBe('changed')
    }
    expect(({} as Record<string, unknown>).id1).toBeUndefined()
  })

  it.each([
    ['lixo', 'não é json {'],
    ['objeto', '{"a":1}'],
    ['itens errados', '[1, null, ["a"], ["a", 2], {"x":1}]'],
    ['vazio', ''],
  ])('armazenamento corrompido (%s) é ignorado, não derruba', (_, raw) => {
    data.set('plany:servers', raw)
    expect(trustOf('Casa', 'abc')).toBe('new')
    remember('Casa', 'abc')
    expect(trustOf('Casa', 'abc')).toBe('same')
  })

  it('sem armazenamento (bloqueado, janela privada, cheio) nada lança e ninguém é avisado', () => {
    vi.stubGlobal('localStorage', {
      getItem: () => {
        throw new Error('bloqueado')
      },
      setItem: () => {
        throw new DOMException('cheio', 'QuotaExceededError')
      },
    })
    expect(() => remember('Casa', 'abc')).not.toThrow()
    expect(trustOf('Casa', 'abc')).toBe('new')
  })
})
