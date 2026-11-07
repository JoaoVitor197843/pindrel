import { describe, expect, it } from 'vitest'
import { autoMark, mergeRuns, parseRuns, plainText, serializeRuns, type Run } from './runs'

const r = (text: string, marks: Run['marks'] = {}): Run => ({ text, marks })

describe('parseRuns', () => {
  it('text without marks is one run', () => {
    expect(parseRuns('olá mundo')).toEqual([r('olá mundo')])
    expect(parseRuns('')).toEqual([])
  })

  it('reads every mark and nests them', () => {
    expect(parseRuns('a **b** *c* __d__ ~~e~~ `f`')).toEqual([
      r('a '), r('b', { bold: true }), r(' '), r('c', { italic: true }), r(' '), r('d', { underline: true }), r(' '), r('e', { strike: true }), r(' '), r('f', { code: true }),
    ])
    expect(parseRuns('**__x__**')).toEqual([r('x', { bold: true, underline: true })])
  })

  it('reads links, their label marks, and decodes what the page escapes', () => {
    expect(parseRuns('[**site**](https://a.com/?x=1&y=2) e <b> & "q"')).toEqual([
      r('site', { bold: true, link: 'https://a.com/?x=1&y=2' }),
      r(' e <b> & "q"'),
    ])
  })

  it('symbols that are not marks stay as text', () => {
    expect(plainText(parseRuns('2 * 3 * 4 e snake_case_name e a ~~ b'))).toBe('2 * 3 * 4 e snake_case_name e a ~~ b')
  })
})

describe('serializeRuns', () => {
  it('round trip for the usual shapes', () => {
    for (const t of ['', 'texto', '**b**', '*i*', '__u__', '~~s~~', '`c`', 'a **b** c *d* e', '**__x__**', '**a *b* c**', '[**site**](https://a.com)', 'x\ny **z**', '2 * 3 * 4', '**negrito** e *itálico* e `código` e [link](https://a.com)']) {
      expect(serializeRuns(parseRuns(t)), t).toBe(t)
    }
  })

  it('merges neighbours with the same marks, so no `****` appears', () => {
    expect(serializeRuns([r('a', { bold: true }), r('b', { bold: true }), r(' c')])).toBe('**ab** c')
    expect(mergeRuns([r('', { bold: true }), r('x')])).toEqual([r('x')])
  })

  it('a mark that starts and ends inside another stays nested', () => {
    expect(serializeRuns([r('a', { bold: true }), r('b', { bold: true, italic: true }), r('c', { bold: true })])).toBe('**a*b*c**')
  })

  it('code holds no other marks', () => {
    expect(serializeRuns([r('a', { bold: true }), r('x', { code: true }), r('b', { bold: true })])).toBe('**a**`x`**b**')
  })

  it('stays stable: text that goes through twice does not change again', () => {
    for (const t of ['**a** **b**', '*a**b**c*', '__a *b* c__', '~~**a**~~ x', '`a` `b`', '***a***']) {
      const once = serializeRuns(parseRuns(t))
      expect(serializeRuns(parseRuns(once)), t).toBe(once)
    }
  })

  it('never throws nor takes long with strange text', () => {
    const t0 = performance.now()
    for (const t of ['*', '**', '***', '~~', '`', '[', '](', '*'.repeat(4000), '**a'.repeat(1500), '[a](b'.repeat(500), '`'.repeat(3001), '_ '.repeat(3000)]) {
      expect(() => serializeRuns(parseRuns(t))).not.toThrow()
    }
    expect(performance.now() - t0).toBeLessThan(2000)
  })
})

describe('autoMark', () => {
  it('sees a mark that was just closed', () => {
    expect(autoMark('uma **frase**')).toEqual({ from: 4, to: 13, inner: 'frase', mark: 'bold' })
    expect(autoMark('uma *frase*')).toEqual({ from: 4, to: 11, inner: 'frase', mark: 'italic' })
    expect(autoMark('uma _frase_')).toMatchObject({ mark: 'italic' })
    expect(autoMark('__x__')).toEqual({ from: 0, to: 5, inner: 'x', mark: 'underline' })
    expect(autoMark('a ~~x y~~')).toMatchObject({ mark: 'strike', inner: 'x y' })
    expect(autoMark('a `cod`')).toMatchObject({ mark: 'code', inner: 'cod' })
  })

  it('waits while the closing symbol is not complete', () => {
    expect(autoMark('uma **frase*')).toBeNull()
    expect(autoMark('uma **frase')).toBeNull()
    expect(autoMark('uma ~frase~')).toBeNull()
  })

  it('does not fire on arithmetic, snake_case, spaces inside or lone symbols', () => {
    for (const t of ['2 * 3 *', 'snake_case_', 'a ** b **', '* a *', '**', '****', '~~~~', '``', 'a*b*', 'c++']) expect(autoMark(t), t).toBeNull()
  })

  it('works on long paragraphs without scanning them whole', () => {
    const long = 'palavra '.repeat(5000)
    expect(autoMark(long + '**fim**')).toMatchObject({ mark: 'bold', inner: 'fim', from: long.length, to: long.length + 7 })
    const t0 = performance.now()
    for (let i = 0; i < 200; i++) autoMark(long + '* *')
    expect(performance.now() - t0).toBeLessThan(500)
  })
})

describe('o que o motor recebe e devolve (de verdade, com marcas aninhadas)', () => {
  it('as quatro marcas juntas viram uma palavra com quatro marcas, e voltam iguais', () => {
    const text = '**__~~*hello*~~__**'
    const runs = parseRuns(text)
    expect(runs).toEqual([r('hello', { bold: true, underline: true, strike: true, italic: true })])
    expect(serializeRuns(runs)).toBe(text)
  })

  it('o mesmo texto, lido de novo e de novo, não ganha símbolos a mais', () => {
    let t = '**hello** e *mundo* e __você__ e ~~eles~~ e `c` e [l](https://a.com)'
    for (let i = 0; i < 4; i++) t = serializeRuns(parseRuns(t))
    expect(t).toBe('**hello** e *mundo* e __você__ e ~~eles~~ e `c` e [l](https://a.com)')
  })

  it('tirar e pôr o negrito de uma palavra com outras marcas não deixa asteriscos soltos', () => {
    const runs = parseRuns('**__hello__**').map((x) => ({ ...x, marks: { ...x.marks } }))
    delete runs[0].marks.bold
    expect(serializeRuns(runs)).toBe('__hello__')
    runs[0].marks.bold = true
    expect(serializeRuns(runs)).toBe('**__hello__**')
  })

  it('marcas que começam no meio: o texto lido de volta tem as mesmas marcas', () => {
    const runs = [r('a ', { bold: true }), r('b', { bold: true, italic: true }), r(' c', { bold: true }), r(' d')]
    expect(parseRuns(serializeRuns(runs))).toEqual(runs)
  })

  it('código com outras marcas e dentro do texto de um link', () => {
    const runs = [r('x', { bold: true, code: true }), r('y', { bold: true }), r(' '), r('l', { link: 'https://a.com', code: true })]
    expect(parseRuns(serializeRuns(runs))).toEqual(runs)
  })
})

describe('autoMark: o símbolo de abertura digitado antes de palavras que já têm o de fechamento', () => {
  it('hello** e depois ** no começo vira negrito', () => {
    expect(autoMark('**', 'hello**')).toEqual({ from: 0, to: 9, inner: 'hello', mark: 'bold' })
    expect(autoMark('frase **', 'hello** fim')).toEqual({ from: 6, to: 15, inner: 'hello', mark: 'bold' })
  })

  it('o primeiro asterisco de **, com ** à frente, ainda não vira itálico', () => {
    expect(autoMark('*', 'hello**')).toBeNull()
    expect(autoMark('*', 'hello*')).toEqual({ from: 0, to: 7, inner: 'hello', mark: 'italic' })
  })

  it('vale para os outros símbolos e não dispara com espaço depois do símbolo', () => {
    expect(autoMark('__', 'oi__')).toMatchObject({ mark: 'underline', inner: 'oi' })
    expect(autoMark('~~', 'oi~~')).toMatchObject({ mark: 'strike' })
    expect(autoMark('`', 'oi`')).toMatchObject({ mark: 'code' })
    expect(autoMark('**', ' hello**')).toBeNull()
    expect(autoMark('**', 'hello **')).toBeNull()
  })
})

describe('marcas com espaço na ponta (selecionar "hello " inteiro)', () => {
  it('os espaços saem da marca, para o símbolo continuar colado nas palavras', () => {
    expect(serializeRuns([r('hello ', { bold: true }), r('mundo')])).toBe('**hello** mundo')
    expect(serializeRuns([r(' hello', { italic: true })])).toBe(' *hello*')
    expect(serializeRuns([r('  ', { bold: true })])).toBe('  ')
    expect(serializeRuns([r('a b', { bold: true })])).toBe('**a b**')
  })

  it('a marca não atravessa a quebra de linha', () => {
    expect(serializeRuns([r('a\nb', { bold: true })])).toBe('**a**\n**b**')
    expect(parseRuns(serializeRuns([r('a\nb', { bold: true })]))).toEqual([r('a', { bold: true }), r('\n'), r('b', { bold: true })])
  })

  it('e o que sai volta a ser lido como marca', () => {
    expect(parseRuns(serializeRuns([r('hello ', { bold: true })]))).toEqual([r('hello', { bold: true }), r(' ')])
  })
})

describe('marca-texto nos trechos', () => {
  it('lê, escreve e fecha o símbolo na ordem de sempre', () => {
    expect(parseRuns('==oi==')).toEqual([r('oi', { highlight: true })])
    expect(serializeRuns([r('oi', { highlight: true, bold: true })])).toBe('**==oi==**')
    expect(parseRuns('**==oi==**')).toEqual([r('oi', { bold: true, highlight: true })])
    expect(autoMark('uma ==frase==')).toEqual({ from: 4, to: 13, inner: 'frase', mark: 'highlight' })
    expect(autoMark('==', 'oi==')).toMatchObject({ mark: 'highlight', inner: 'oi' })
    expect(autoMark('a == b ==')).toBeNull()
  })
})
