import { describe, expect, it } from 'vitest'
import { ALL_EMOJI, EMOJI_GROUPS, firstEmoji, isEmoji } from './emoji'

describe('isEmoji', () => {
  it('aceita um emoji só: simples, com variação, composto e bandeira', () => {
    for (const e of ['🔥', '🗂️', '⚠️', '🧑‍💻', '👍', '🇧🇷', '❤️']) expect(isEmoji(e), e).toBe(true)
  })

  it('recusa texto, marcação, vários emojis, vazio e exageros', () => {
    for (const bad of ['', ' ', 'a', 'abc', '1', '<b>', '🔥🔥', '🔥 ', ' 🔥', 'a🔥', '🔥a', '<script>🔥</script>', '🔥'.repeat(30), '\u0000', '\n🔥']) expect(isEmoji(bad), JSON.stringify(bad)).toBe(false)
    expect(isEmoji(null as unknown as string)).toBe(false)
    expect(isEmoji(5 as unknown as string)).toBe(false)
  })

  it('toda a lista do seletor é aceita, sem repetição dentro de um grupo', () => {
    expect(ALL_EMOJI.length).toBeGreaterThan(300)
    for (const g of EMOJI_GROUPS) {
      expect(new Set(g.list).size, g.key).toBe(g.list.length)
      for (const e of g.list) expect(isEmoji(e), `${g.key} ${e}`).toBe(true)
      expect(isEmoji(g.sign)).toBe(true)
    }
  })
})

describe('firstEmoji', () => {
  it('acha o primeiro emoji no meio do texto colado', () => {
    expect(firstEmoji('ola 🎉 mundo 🔥')).toBe('🎉')
    expect(firstEmoji('🧑‍💻 dev')).toBe('🧑‍💻')
  })

  it('sem emoji, ou com um texto enorme, não acha nada', () => {
    expect(firstEmoji('sem nada')).toBeNull()
    expect(firstEmoji('')).toBeNull()
    expect(firstEmoji('a'.repeat(10_000) + '🔥')).toBeNull()
  })
})
