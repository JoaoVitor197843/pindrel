import { describe, expect, it } from 'vitest'
import { highlight, MAX_HIGHLIGHT } from './highlight'

const join = (code: string, lang: string) => highlight(code, lang).map((t) => t.t).join('')
const kinds = (code: string, lang: string) => highlight(code, lang).filter((t) => t.k !== 'text').map((t) => `${t.k}:${t.t}`)

describe('highlight', () => {
  it('comentário, string, palavra-chave e número em python', () => {
    expect(kinds('# nota\ndef f(x):\n    return "ok" + 42', 'python')).toEqual(['comment:# nota', 'keyword:def', 'keyword:return', 'string:"ok"', 'number:42'])
  })

  it('o texto é sempre devolvido inteiro, mesmo com aspas e comentários sem fim', () => {
    for (const code of ['"aberta', "'a\\", '/* sem fim', '`x\ny', '\n\n', '', '💥 emoji "é"', 'x = 1_000.5e3']) {
      for (const lang of ['python', 'javascript', 'sql', 'texto', 'desconhecida']) expect(join(code, lang)).toBe(code)
    }
  })

  it('texto simples não ganha cor', () => {
    expect(kinds('def "x" 12 # y', 'texto')).toEqual([])
  })

  it('string sem fim vai só até o fim da linha', () => {
    expect(kinds('a = "abc\nb = 1', 'python')).toEqual(['string:"abc', 'number:1'])
  })

  it('número dentro de identificador não é número; sql ignora a caixa', () => {
    expect(kinds('abc123 x2', 'python')).toEqual([])
    expect(kinds('SELECT 1 FROM t', 'sql')).toEqual(['keyword:SELECT', 'number:1', 'keyword:FROM'])
  })

  it('texto enorme é cortado para colorir, sem perder nada e sem travar', () => {
    const big = 'def x(): return 1\n'.repeat(5000)
    const t0 = performance.now()
    expect(join(big, 'python')).toBe(big)
    expect(big.length).toBeGreaterThan(MAX_HIGHLIGHT)
    expect(performance.now() - t0).toBeLessThan(1000)
  })

  it('aspas dentro de comentário não abrem string', () => {
    expect(kinds("// it's fine\nlet a = 1", 'javascript')).toEqual(["comment:// it's fine", 'keyword:let', 'number:1'])
  })
})
