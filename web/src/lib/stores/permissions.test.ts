import { describe, expect, it } from 'vitest'
import { ALL_PERMS, PERMS, describePerms, levelOf, normalizePerms, permsFor } from './permissions'

describe('permissions', () => {
  it('"editar tudo" é tudo liberado; "somente leitura" é nada; o meio é personalizado', () => {
    expect(levelOf(ALL_PERMS)).toBe('edit')
    expect(levelOf([])).toBe('read')
    expect(levelOf(['text'])).toBe('custom')
    expect(levelOf(ALL_PERMS.filter((k) => k !== 'share'))).toBe('custom')
    expect(permsFor('edit')).toEqual(ALL_PERMS)
    expect(permsFor('read')).toEqual([])
    expect(permsFor('edit')).not.toBe(ALL_PERMS) // a copy: editing it never changes the list of all permissions
  })

  it('a lista cobre o que foi pedido (compartilhar, tags, imagens...) sem repetir chave', () => {
    const keys = PERMS.map((p) => p.key)
    expect(new Set(keys).size).toBe(keys.length)
    for (const k of ['share', 'tags', 'images', 'delete', 'export', 'secure', 'blocks', 'tables', 'text', 'checklist']) expect(keys).toContain(k)
    expect(PERMS.every((p) => p.label && p.hint)).toBe(true)
  })

  it('normalizePerms descarta o desconhecido e o repetido e mantém a ordem', () => {
    expect(normalizePerms(['tags', 'text', 'tags', 'admin', 42, null, '__proto__'])).toEqual(['text', 'tags'])
    for (const bad of [undefined, null, 'text', 5, {}, { length: 1 }]) expect(normalizePerms(bad)).toEqual([])
  })

  it('descreve o acesso em português', () => {
    expect(describePerms(ALL_PERMS)).toBe('Editar tudo')
    expect(describePerms([])).toBe('Somente leitura')
    expect(describePerms(['text', 'tags'])).toBe('Personalizado (2 de 10)')
  })
})
