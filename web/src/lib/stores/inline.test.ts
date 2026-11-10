import { describe, expect, it } from 'vitest'
import { inlineHtml, makeLink, markdownMarks, renderMarks, safeUrl, toggleMark } from './inline'
import { escapeHtml } from './transfer'

describe('toggleMark', () => {
  it('envolve a seleção e deixa os marcadores colados nas palavras', () => {
    expect(toggleMark('uma frase boa', 4, 9, 'bold')).toEqual({ text: 'uma **frase** boa', start: 6, end: 11 })
    expect(toggleMark('uma frase boa', 3, 10, 'italic')?.text).toBe('uma *frase* boa')
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
    expect(html('**a** e *b* e _d_ e `c`')).toBe('<strong>a</strong> e <em>b</em> e <em>d</em> e <code>c</code>')
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
  it('liga e desliga com __', () => {
    expect(toggleMark('uma frase boa', 4, 9, 'underline')).toEqual({ text: 'uma __frase__ boa', start: 6, end: 11 })
    expect(toggleMark('uma __frase__ boa', 6, 11, 'underline')).toEqual({ text: 'uma frase boa', start: 4, end: 9 })
  })

  it('combina com negrito e itálico, em qualquer ordem', () => {
    const a = toggleMark('x frase y', 2, 7, 'bold')!
    const b = toggleMark(a.text, a.start, a.end, 'underline')!
    expect(b.text).toBe('x **__frase__** y')
    expect(html(b.text)).toBe('x <strong><u>frase</u></strong> y')
  })

  const html = (t: string) => inlineHtml(t)

  it('vira <u>, nunca dentro de código, e só com texto de verdade entre os marcadores', () => {
    expect(html('a __b__ c')).toBe('a <u>b</u> c')
    expect(html('`__b__`')).toBe('<code>__b__</code>')
    expect(html('1 __ 2')).toBe('1 __ 2')
    expect(html('____')).toBe('____')
    expect(html('__ a __')).toBe('__ a __')
    expect(html('snake__case__name')).toBe('snake__case__name')
    expect(html('(__a__) e __b c__.')).toBe('(<u>a</u>) e <u>b c</u>.')
    expect(html('c++ e i++ e ++a++')).toBe('c++ e i++ e ++a++')
  })

  it('o texto com __ aparece sublinhado fora da edição, e sem marcas continua só um campo', () => {
    expect(renderMarks('um __sublinhado__')).toBe('um <u>sublinhado</u>')
    expect(renderMarks('2 + 2 = 4')).toBeNull()
    expect(renderMarks('<u>x</u> __y__')).toBe('&lt;u&gt;x&lt;/u&gt; <u>y</u>')
  })

  it('o markdown exportado usa <u> (em markdown __ seria negrito), e deixa o código em paz', () => {
    expect(markdownMarks('a __b__ e `__c__`')).toBe('a <u>b</u> e `__c__`')
    expect(markdownMarks('sem nada')).toBe('sem nada')
  })
})

describe('riscado', () => {
  const html = (t: string) => inlineHtml(escapeHtml(t))

  it('liga e desliga com ~~', () => {
    expect(toggleMark('uma frase boa', 4, 9, 'strike')).toEqual({ text: 'uma ~~frase~~ boa', start: 6, end: 11 })
    expect(toggleMark('uma ~~frase~~ boa', 6, 11, 'strike')).toEqual({ text: 'uma frase boa', start: 4, end: 9 })
    expect(toggleMark('uma ~~frase~~ boa', 4, 13, 'strike')?.text).toBe('uma frase boa')
  })

  it('vira <s> só com texto colado nos marcadores', () => {
    expect(html('a ~~b~~ c')).toBe('a <s>b</s> c')
    expect(html('~~a b~~')).toBe('<s>a b</s>')
    expect(html('`~~b~~`')).toBe('<code>~~b~~</code>')
    expect(html('a ~~ b ~~ c')).toBe('a ~~ b ~~ c')
    expect(html('~~~~')).toBe('~~~~')
    expect(html('~~~a~~~')).toBe('~~~a~~~')
    expect(html('**~~a~~**')).toBe('<strong><s>a</s></strong>')
  })

  it('o markdown exportado mantém ~~ (é o padrão do GFM)', () => {
    expect(markdownMarks('a ~~b~~')).toBe('a ~~b~~')
  })
})

describe('itálico com asterisco', () => {
  const html = (t: string) => inlineHtml(escapeHtml(t))

  it('o asterisco do negrito não é confundido com o do itálico, ao ligar e desligar', () => {
    expect(toggleMark('x frase y', 2, 7, 'italic')?.text).toBe('x *frase* y')
    expect(toggleMark('x **frase** y', 4, 9, 'italic')?.text).toBe('x ***frase*** y')
    expect(toggleMark('x ***frase*** y', 5, 10, 'italic')?.text).toBe('x **frase** y')
    expect(toggleMark('x ***frase*** y', 5, 10, 'bold')?.text).toBe('x *frase* y')
    expect(toggleMark('x **frase** y', 2, 11, 'italic')?.text).toBe('x ***frase*** y')
    expect(toggleMark('x *frase* y', 2, 9, 'italic')?.text).toBe('x frase y')
  })

  it('negrito e itálico juntos desenham os dois', () => {
    expect(html('***a***')).toBe('<strong><em>a</em></strong>')
    expect(html('*a* e **b**')).toBe('<em>a</em> e <strong>b</strong>')
  })

  it('conta, asteriscos soltos e nota de rodapé não viram itálico', () => {
    expect(html('2 * 3 * 4')).toBe('2 * 3 * 4')
    expect(html('a*b*c')).toBe('a*b*c')
    expect(html('* item')).toBe('* item')
    expect(html('**')).toBe('**')
    expect(html('* a *')).toBe('* a *')
  })
})

describe('marcas e links', () => {
  const html = (t: string) => inlineHtml(escapeHtml(t))

  it('marcas funcionam dentro do texto do link, mas nunca dentro do endereço', () => {
    expect(html('[**site**](https://a.com/*x*/__y__/~~z~~)')).toBe('<a href="https://a.com/*x*/__y__/~~z~~" rel="noopener noreferrer"><strong>site</strong></a>')
    expect(html('*a* [b](https://a.com) *c*')).toBe('<em>a</em> <a href="https://a.com" rel="noopener noreferrer">b</a> <em>c</em>')
  })

  it('texto estranho nunca quebra nem trava: marcadores soltos, enormes e repetidos', () => {
    for (const t of ['*', '**', '***', '~~', '~', '__', '_', '*'.repeat(5000), '~'.repeat(5001), '_'.repeat(5000), '* '.repeat(3000), '**a'.repeat(2000), '[a](b'.repeat(500)]) {
      expect(() => inlineHtml(escapeHtml(t))).not.toThrow()
    }
    const t0 = performance.now()
    inlineHtml(escapeHtml('*a '.repeat(8000)))
    inlineHtml(escapeHtml('~~a '.repeat(8000)))
    inlineHtml(escapeHtml('__a '.repeat(8000)))
    // a quadratic reader needs minutes here; the margin is for a CI runner shared by four jobs
    expect(performance.now() - t0).toBeLessThan(6000)
  })
})

describe('marcas dentro de marcas', () => {
  const html = (t: string) => inlineHtml(escapeHtml(t))

  it('as quatro marcas juntas na mesma palavra, em qualquer ordem de abertura', () => {
    expect(html('**__~~*hello*~~__**')).toBe('<strong><u><s><em>hello</em></s></u></strong>')
    // the tags always nest in the same order, whichever way the markers were opened
    expect(html('*~~__**hello**__~~*')).toBe('<strong><u><s><em>hello</em></s></u></strong>')
    expect(html('**__hello__**')).toBe('<strong><u>hello</u></strong>')
  })

  it('itálico dentro de negrito e de sublinhado, com texto solto em volta', () => {
    expect(html('**a *b* c**')).toBe('<strong>a <em>b</em> c</strong>')
    expect(html('x __a *b* c__ y')).toBe('x <u>a <em>b</em> c</u> y')
    expect(html('**a** *b* __c__ ~~d~~')).toBe('<strong>a</strong> <em>b</em> <u>c</u> <s>d</s>')
  })

  it('código e links dentro de marcas, e marcas dentro do texto do link', () => {
    expect(html('**a `b` c**')).toBe('<strong>a <code>b</code> c</strong>')
    expect(html('**[site](https://a.com)**')).toBe('<a href="https://a.com" rel="noopener noreferrer"><strong>site</strong></a>')
    expect(html('[**site** e *outro*](https://a.com)')).toBe('<a href="https://a.com" rel="noopener noreferrer"><strong>site</strong> e <em>outro</em></a>')
  })

  it('marca aberta e nunca fechada fica como texto, sem estragar o resto', () => {
    expect(html('hello** e *b*')).toBe('hello** e <em>b</em>')
    expect(html('**hello e *b*')).toBe('**hello e <em>b</em>')
    expect(html('a *b e __c__')).toBe('a *b e <u>c</u>')
  })

  it('uma marca não atravessa linhas', () => {
    expect(html('**a\nb**')).toBe('**a\nb**')
  })

  it('profundidade absurda e entradas feitas para travar terminam rápido', () => {
    const t0 = performance.now()
    inlineHtml(escapeHtml('*a '.repeat(8000)))
    inlineHtml(escapeHtml('**a *b '.repeat(3000)))
    inlineHtml(escapeHtml('*'.repeat(9000)))
    inlineHtml(escapeHtml('*_~`['.repeat(2000)))
    inlineHtml(escapeHtml('('.repeat(40) + '*a*' + ')'.repeat(40)))
    expect(performance.now() - t0).toBeLessThan(2000)
  })
})

describe('marca-texto ==x==', () => {
  const html = (t: string) => inlineHtml(escapeHtml(t))

  it('liga e desliga e vira <mark>', () => {
    expect(toggleMark('uma frase boa', 4, 9, 'highlight')).toEqual({ text: 'uma ==frase== boa', start: 6, end: 11 })
    expect(toggleMark('uma ==frase== boa', 6, 11, 'highlight')).toEqual({ text: 'uma frase boa', start: 4, end: 9 })
    expect(html('a ==b== c')).toBe('a <mark>b</mark> c')
  })

  it('junto das outras marcas, em qualquer lado', () => {
    expect(html('**==a==**')).toBe('<strong><mark>a</mark></strong>')
    // the tags always nest in the same order, so a mark that wraps a bold word is cut around it
    expect(html('==**a** e *b*==')).toBe('<strong><mark>a</mark></strong><mark> e <em>b</em></mark>')
  })

  it('comparações e código com == não são marca-texto', () => {
    for (const t of ['a == b', 'x==y==z', 'a === b === c', '====', '== a ==', 'if (a==b) c==d']) expect(html(t), t).toBe(t)
    expect(html('`==x==`')).toBe('<code>==x==</code>')
  })

  it('o markdown exportado usa <mark>, menos no código', () => {
    expect(markdownMarks('a ==b== e `==c==`')).toBe('a <mark>b</mark> e `==c==`')
  })
})
