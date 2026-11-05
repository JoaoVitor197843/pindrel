import { describe, expect, it } from 'vitest'
import { inlineHtml, makeLink, markdownMarks, renderMarks, safeUrl, toggleMark } from './inline'
import { escapeHtml } from './transfer'

describe('toggleMark', () => {
  it('envolve a seleção e deixa os marcadores colados nas palavras', () => {
    expect(toggleMark('uma frase boa', 4, 9, 'bold')).toEqual({ text: 'uma **frase** boa', start: 6, end: 11 })
    expect(toggleMark('uma frase boa', 3, 10, 'italic')?.text).toBe('uma _frase_ boa')
    expect(toggleMark('x = 1', 0, 5, 'code')?.text).toBe('`x = 1`')
  })

  it('tira o marcador quando a seleção já está dentro dele, ou o inclui', () => {
    expect(toggleMark('uma **frase** boa', 6, 11, 'bold')).toEqual({ text: 'uma frase boa', start: 4, end: 9 })
    expect(toggleMark('uma **frase** boa', 4, 13, 'bold')?.text).toBe('uma frase boa')
  })

  it('seleção vazia, só espaços ou fora do texto não muda nada', () => {
    expect(toggleMark('abc', 1, 1, 'bold')).toBeNull()
    expect(toggleMark('a   b', 1, 4, 'bold')).toBeNull()
    expect(toggleMark('abc', -1, 2, 'bold')).toBeNull()
    expect(toggleMark('abc', 0, 99, 'bold')).toBeNull()
    expect(toggleMark('abc', NaN, 2, 'bold')).toBeNull()
  })

  it('aceita a seleção feita de trás para frente', () => {
    expect(toggleMark('uma frase', 9, 4, 'bold')?.text).toBe('uma **frase**')
  })
})

describe('safeUrl e makeLink', () => {
  it('aceita http, https, e-mail e domínio solto', () => {
    expect(safeUrl('https://exemplo.com/a?b=1')).toBe('https://exemplo.com/a?b=1')
    expect(safeUrl('exemplo.com')).toBe('https://exemplo.com')
    expect(safeUrl('ana@exemplo.com')).toBe('mailto:ana@exemplo.com')
  })

  it('recusa javascript:, data:, espaços, aspas e o que não é endereço', () => {
    for (const bad of ['javascript:alert(1)', 'JaVaScRiPt:alert(1)', 'data:text/html,x', 'vbscript:x', 'a b.com', '"x".com', 'abc', '', '   ', 'http://a.com/"x']) {
      expect(safeUrl(bad), bad).toBeNull()
    }
    expect(safeUrl('https://a.com/' + 'x'.repeat(2100))).toBeNull()
  })

  it('parênteses do endereço não quebram o link', () => {
    expect(safeUrl('https://a.com/x_(y)')).toBe('https://a.com/x_%28y%29')
  })

  it('cria o link e seleciona o texto dele', () => {
    expect(makeLink('veja o site agora', 7, 11, 'exemplo.com')).toEqual({ text: 'veja o [site](https://exemplo.com) agora', start: 8, end: 12 })
    expect(makeLink('abc', 1, 1, 'a.com')).toBeNull()
    expect(makeLink('abc', 0, 3, 'javascript:x')).toBeNull()
    expect(makeLink('a[b]c', 0, 5, 'a.com')?.text).toBe('[abc](https://a.com)')
  })
})

describe('inlineHtml', () => {
  const html = (t: string) => inlineHtml(escapeHtml(t))

  it('converte negrito, itálico, código e links seguros', () => {
    expect(html('**a** e _b_ e `c`')).toBe('<strong>a</strong> e <em>b</em> e <code>c</code>')
    expect(html('[site](https://a.com/x?y=1&z=2)')).toBe('<a href="https://a.com/x?y=1&amp;z=2" rel="noopener noreferrer">site</a>')
  })

  it('não formata dentro de código nem no meio de palavras_com_sublinhado', () => {
    expect(html('`**x**`')).toBe('<code>**x**</code>')
    expect(html('snake_case_name')).toBe('snake_case_name')
  })

  it('nunca deixa HTML nem esquema perigoso passar', () => {
    expect(html('<img src=x onerror=alert(1)>')).not.toContain('<img')
    expect(html('[x](javascript:alert(1))')).not.toContain('<a')
    expect(html('[x](https://a.com"onmouseover="alert(1))')).not.toContain('onmouseover="')
    expect(html('**<script>**')).toBe('<strong>&lt;script&gt;</strong>')
  })
})

describe('sublinhado', () => {
  it('liga e desliga com ++', () => {
    expect(toggleMark('uma frase boa', 4, 9, 'underline')).toEqual({ text: 'uma ++frase++ boa', start: 6, end: 11 })
    expect(toggleMark('uma ++frase++ boa', 6, 11, 'underline')).toEqual({ text: 'uma frase boa', start: 4, end: 9 })
  })

  it('combina com negrito e itálico, em qualquer ordem', () => {
    const a = toggleMark('x frase y', 2, 7, 'bold')!
    const b = toggleMark(a.text, a.start, a.end, 'underline')!
    expect(b.text).toBe('x **++frase++** y')
    expect(html(b.text)).toBe('x <strong><u>frase</u></strong> y')
  })

  const html = (t: string) => inlineHtml(t)

  it('vira <u>, nunca dentro de código, e só com texto de verdade entre os marcadores', () => {
    expect(html('a ++b++ c')).toBe('a <u>b</u> c')
    expect(html('`++b++`')).toBe('<code>++b++</code>')
    expect(html('1 + 1 ++ 2')).toBe('1 + 1 ++ 2')
    expect(html('++++')).toBe('++++')
    expect(html('c++ e c++')).toBe('c++ e c++')
    expect(html('i++ e j++ , k++')).toBe('i++ e j++ , k++')
    expect(html('++ a ++')).toBe('++ a ++')
    expect(html('(++a++) e ++b c++.')).toBe('(<u>a</u>) e <u>b c</u>.')
  })

  it('o texto com ++ aparece sublinhado fora da edição, e sem marcas continua só um campo', () => {
    expect(renderMarks('um ++sublinhado++')).toBe('um <u>sublinhado</u>')
    expect(renderMarks('2 + 2 = 4')).toBeNull()
    expect(renderMarks('<u>x</u> ++y++')).toBe('&lt;u&gt;x&lt;/u&gt; <u>y</u>')
  })

  it('o markdown exportado usa <u>, e deixa o código em paz', () => {
    expect(markdownMarks('a ++b++ e `++c++`')).toBe('a <u>b</u> e `++c++`')
    expect(markdownMarks('sem nada')).toBe('sem nada')
  })
})
