import { describe, expect, it, vi } from 'vitest'
import { sampleWorkspace } from '../sample'
import { download, escapeHtml, exportPage, fileNameFor, pageToHtml, pageToJson, pageToMarkdown, pageToText, parseImported, readImports, toJson, toMarkdown } from './transfer'
import { Workspace } from './workspace.svelte'
import type { NotePage } from './workspace.svelte'

const file = (name: string, text: string, size = text.length) => {
  const f = new File([text], name)
  Object.defineProperty(f, 'size', { value: size })
  f.text = async () => text
  return f
}

describe('exportar', () => {
  const w = sampleWorkspace()

  it('JSON e Markdown deixam de fora o que é do cofre e o que está na lixeira', () => {
    w.trash('p1')
    const json = JSON.parse(toJson(w.pages, w.tags))
    const titles = json.pages.map((p: { title: string }) => p.title)
    expect(titles).not.toContain('Senhas e chaves de recuperação')
    expect(titles).not.toContain('Reforma do apartamento — orçamento')
    expect(titles).toContain('Pão de fermentação natural')
    expect(json.pages[0].tags.every((t: string) => typeof t === 'string')).toBe(true)
    const md = toMarkdown(w.pages, w.tags)
    expect(md).toContain('# Pão de fermentação natural')
    expect(md).not.toContain('Conteúdo protegido')
    expect(md).toContain('tags: receitas')
  })

  it('download devolve false quando o navegador não consegue gerar o arquivo', () => {
    URL.createObjectURL = vi.fn(() => {
      throw new Error('no')
    })
    expect(download('a.json', '{}', 'application/json')).toBe(false)
  })

  it('download clica num link temporário e solta a URL', () => {
    vi.useFakeTimers()
    URL.createObjectURL = vi.fn(() => 'blob:x')
    URL.revokeObjectURL = vi.fn()
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    expect(download('a.json', '{}', 'application/json')).toBe(true)
    expect(click).toHaveBeenCalledOnce()
    vi.runAllTimers()
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:x')
    click.mockRestore()
    vi.useRealTimers()
  })
})

describe('importar', () => {
  it('o primeiro título do markdown vira o título; sem ele, o nome do arquivo', () => {
    expect(parseImported('x.md', '# Receita\n\nmisture tudo')).toEqual({ title: 'Receita', excerpt: 'misture tudo' })
    expect(parseImported('minha nota.txt', 'só texto\r\nem duas linhas')).toEqual({ title: 'minha nota', excerpt: 'só texto em duas linhas' })
    expect(parseImported('.md', '').title).toBe('Sem título')
  })

  it('título e resumo têm limite, mesmo com arquivo enorme', () => {
    const r = parseImported('x.md', `# ${'t'.repeat(500)}\n${'a '.repeat(5000)}`)
    expect(r.title).toHaveLength(120)
    expect(r.excerpt.length).toBeLessThanOrEqual(240)
  })

  it('só lê .md/.txt pequenos, no máximo 20 arquivos; o resto é contado como ignorado', async () => {
    const files = [file('a.md', '# A'), file('b.exe', 'MZ'), file('c.txt', 'c'), file('grande.md', 'x', 5_000_000)]
    const r = await readImports(files)
    expect(r.pages.map((p) => p.title)).toEqual(['A', 'c'])
    expect(r.skipped).toBe(2)
    const many = await readImports(Array.from({ length: 30 }, (_, i) => file(`${i}.md`, `# ${i}`)))
    expect(many.pages).toHaveLength(20)
    expect(many.skipped).toBe(10)
  })

  it('um arquivo que não consegue ser lido não derruba os outros', async () => {
    const bad = file('ruim.md', 'x')
    bad.text = async () => {
      throw new Error('boom')
    }
    const r = await readImports([bad, file('ok.md', '# Ok')])
    expect(r.pages.map((p) => p.title)).toEqual(['Ok'])
    expect(r.skipped).toBe(1)
  })
})

describe('exportar uma página', () => {
  const w = sampleWorkspace()
  const page = w.page('p0')!
  const md = pageToMarkdown(page, w.tags)

  it('Markdown: título, tags e cada tipo de bloco no formato certo', () => {
    expect(md.startsWith('# Rotina de encerramento do trimestre\n\ntags: operações, trimestral, cofre\n\n')).toBe(true)
    expect(md).toContain('## O que precisa acontecer antes do dia 31')
    expect(md).toContain('- [x] Fechar conciliação dos lançamentos de março')
    expect(md).toContain('- [ ] Rodar o export do relatório do conselho')
    expect(md).toContain('```python\n# rotina noturna')
    expect(md).toContain('<details><summary>spoiler</summary>')
    expect(md).toContain('| Frente | Responsável | Prazo |\n| --- | --- | --- |\n| Conciliação | Marina | 24 mar |')
  })

  it('o bloco seguro fica de fora, a menos que peçam', () => {
    expect(md).not.toContain('PNDR-4471')
    expect(md).toContain('[bloco seguro omitido]')
    expect(pageToMarkdown(page, w.tags, { includeSecure: true })).toContain('PNDR-4471')
    for (const f of ['md', 'html', 'txt', 'json'] as const) {
      expect(exportPage(page, w.tags, f)).not.toContain('PNDR-4471')
      expect(exportPage(page, w.tags, f, { includeSecure: true })).toContain('PNDR-4471')
    }
  })

  it('texto simples e JSON', () => {
    const txt = pageToText(page, w.tags)
    expect(txt).toContain('O QUE PRECISA ACONTECER ANTES DO DIA 31')
    expect(txt).toContain('[x] Fechar conciliação')
    expect(txt).toContain('Frente\tResponsável\tPrazo')
    const json = JSON.parse(pageToJson(page, w.tags))
    expect(json).toMatchObject({ app: 'pindrel', title: page.title, tags: ['operações', 'trimestral', 'cofre'] })
    expect(json.blocks).toHaveLength(7)
    expect(json.blocks.find((b: { type: string }) => b.type === 'secure')).toMatchObject({ omitted: true })
    expect(JSON.stringify(json)).not.toContain('PNDR')
  })

  it('HTML: documento completo, em português, sem script', () => {
    const html = pageToHtml(page, w.tags)
    expect(html).toContain('<!doctype html>')
    expect(html).toContain('<html lang="pt-BR">')
    expect(html).toContain('<table>')
    expect(html).toContain('<details><summary>spoiler</summary>')
    expect(html).not.toMatch(/<script/i)
  })

  it('nada do que a pessoa escreveu vira marcação no HTML exportado', () => {
    const w2 = sampleWorkspace()
    const p = w2.newPage('<img src=x onerror=alert(1)> & "aspas"')
    p.content = [
      { id: 'a', type: 'paragraph', text: '<script>alert(1)</script>\nsegunda linha' },
      { id: 'b', type: 'code', lang: 'html', text: '</code></pre><script>x</script>' },
      { id: 'c', type: 'checklist', items: [{ id: 'i', text: '<b>x</b>', done: true }] },
      { id: 'd', type: 'table', cols: [{ id: 'k', label: '<th>', w: 100 }], rows: [{ k: '</td><script>' }] },
      { id: 'e', type: 'image', name: '"><script>', src: null },
    ]
    const html = pageToHtml(p, w2.tags)
    expect(html).not.toMatch(/<script/i)
    expect(html).not.toContain('<img')
    expect(html).not.toContain('<b>x</b>')
    expect(html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;<br>segunda linha')
    expect(escapeHtml(`&<>"'`)).toBe('&amp;&lt;&gt;&quot;&#39;')
  })

  it('o Markdown aguenta crases, barras e quebras dentro do conteúdo', () => {
    const w2 = sampleWorkspace()
    const p = w2.newPage('Título\ncom quebra')
    p.content = [
      { id: 'a', type: 'code', lang: 'texto', text: 'texto com ``` dentro\n```' },
      { id: 'b', type: 'table', cols: [{ id: 'k', label: 'a|b', w: 100 }], rows: [{ k: 'x|y\nz' }] },
      { id: 'c', type: 'heading', text: 'linha 1\nlinha 2' },
    ]
    const out = pageToMarkdown(p, w2.tags)
    expect(out.startsWith('# Título com quebra\n')).toBe(true)
    expect(out).toContain('````\ntexto com ``` dentro\n```\n````')
    expect(out).toContain('| a\\|b |')
    expect(out).toContain('| x\\|y z |')
    expect(out).toContain('## linha 1 linha 2')
  })

  it('uma página nunca aberta exporta o resumo; uma vazia exporta só o título', () => {
    expect(pageToMarkdown(w.page('p5')!, w.tags)).toContain('Levain')
    const empty = w.newPage()
    expect(pageToMarkdown(empty, w.tags)).toBe('# Sem título\n\n')
  })

  it('nome do arquivo é seguro: sem barras, acentos nem pontos no começo; nunca vazio', () => {
    expect(fileNameFor('Rotina de encerramento — Q1', 'md')).toBe('Rotina-de-encerramento-Q1.md')
    expect(fileNameFor('../../etc/passwd', 'md')).toBe('etc-passwd.md')
    expect(fileNameFor('...', 'txt')).toBe('pagina.txt')
    expect(fileNameFor('', 'json')).toBe('pagina.json')
    expect(fileNameFor('a'.repeat(300), 'md').length).toBeLessThanOrEqual(63)
    expect(fileNameFor('CON: <>|?*', 'md')).toMatch(/^[A-Za-z0-9._-]+\.md$/)
  })

  it('a exportação geral usa o conteúdo das páginas e continua sem o cofre', () => {
    const all = toMarkdown(w.pages, w.tags)
    expect(all).toContain('- [x] Fechar conciliação')
    expect(all).not.toContain('seed de 24 palavras')
    expect(all).not.toContain('PNDR')
    const json = JSON.parse(toJson(w.pages, w.tags))
    expect(json.pages.some((p: { title: string }) => p.title === 'Contas bancárias e PIX')).toBe(false)
    expect(json.pages.find((p: { title: string }) => p.title.startsWith('Rotina')).content).toHaveLength(7)
  })
})


describe('exportação dos blocos novos', () => {
  const page = (): NotePage => ({
    ...sampleWorkspace().page('p0')!,
    title: 'T',
    tags: [],
    content: [
      { id: 'a', type: 'quote', text: 'linha 1\nlinha 2' },
      { id: 'b', type: 'callout', text: 'cuidado' },
      { id: 'c', type: 'toggle', text: 'mais', body: 'escondido' },
      { id: 'd', type: 'divider' },
      { id: 'e', type: 'paragraph', text: '**forte** e [site](https://a.com) <b>x</b>' },
    ],
  })

  it('markdown', () => {
    const md = pageToMarkdown(page(), [])
    expect(md).toContain('> linha 1\n> linha 2')
    expect(md).toContain('> [!NOTE]\n> cuidado')
    expect(md).toContain('<details><summary>mais</summary>\n\nescondido\n\n</details>')
    expect(md).toContain('\n---\n')
    expect(md).toContain('**forte** e [site](https://a.com)')
  })

  it('texto simples', () => {
    const txt = pageToText(page(), [])
    expect(txt).toContain('> linha 1')
    expect(txt).toContain('Nota: cuidado')
    expect(txt).toContain('mais\nescondido')
    expect(txt).toContain('----------')
  })

  it('html converte as marcas e escapa todo o resto', () => {
    const html = pageToHtml(page(), [])
    expect(html).toContain('<blockquote>linha 1<br>linha 2</blockquote>')
    expect(html).toContain('<aside class="callout info">cuidado</aside>')
    expect(html).toContain('<details><summary>mais</summary><p>escondido</p></details>')
    expect(html).toContain('<hr>')
    expect(html).toContain('<strong>forte</strong>')
    expect(html).toContain('<a href="https://a.com" rel="noopener noreferrer">site</a>')
    expect(html).toContain('&lt;b&gt;x&lt;/b&gt;')
    expect(html).not.toContain('<b>x</b>')
  })
})

describe('sublinhado na exportação', () => {
  const page = (): NotePage => ({
    ...sampleWorkspace().page('p0')!,
    title: 'T',
    tags: [],
    content: [
      { id: 'a', type: 'paragraph', text: 'um __sublinhado__ e **forte** e ~~cortado~~' },
      { id: 'b', type: 'heading', text: 'título __sublinhado__' },
      { id: 'c', type: 'quote', text: '__citação__' },
      { id: 'd', type: 'code', lang: 'texto', text: 'i++ e j++' },
    ],
  })

  it('markdown troca __ por <u> e mantém ~~, menos no código', () => {
    const md = pageToMarkdown(page(), [])
    expect(md).toContain('um <u>sublinhado</u> e **forte** e ~~cortado~~')
    expect(md).toContain('## título <u>sublinhado</u>')
    expect(md).toContain('> <u>citação</u>')
    expect(md).toContain('i++ e j++')
  })

  it('html faz <u> e escapa o resto', () => {
    const html = pageToHtml(page(), [])
    expect(html).toContain('um <u>sublinhado</u> e <strong>forte</strong> e <s>cortado</s>')
    expect(html).toContain('<h2>título <u>sublinhado</u></h2>')
    expect(html).toContain('<code>i++ e j++</code>')
  })
})

describe('exportação: títulos, listas, sumário, link e destaques', () => {
  const page = (): NotePage => {
    const w = sampleWorkspace()
    const p = w.page('p5')!
    p.title = 'Teste'
    p.content = [
      { id: 'a', type: 'heading', text: 'Grande', level: 1 },
      { id: 'b', type: 'heading', text: 'Médio' },
      { id: 'c', type: 'heading', text: 'Pequeno', level: 3 },
      { id: 'd', type: 'toc' },
      { id: 'e', type: 'bullet', text: 'um **forte**', indent: 0 },
      { id: 'f', type: 'bullet', text: 'filho', indent: 1 },
      { id: 'g', type: 'numbered', text: 'primeiro', indent: 0 },
      { id: 'h', type: 'numbered', text: 'segundo', indent: 0 },
      { id: 'i', type: 'paragraph', text: 'fim' },
      { id: 'j', type: 'bookmark', url: 'https://exemplo.com/a?x=1&y=2', title: 'Meu <site>' },
      { id: 'k', type: 'callout', text: 'cuidado', tone: 'warning' },
      { id: 'l', type: 'callout', text: 'ok', tone: 'success' },
      { id: 'm', type: 'callout', text: 'nota' },
    ]
    return p
  }

  it('markdown: # por tamanho, listas coladas, números certos, sumário em lista, link e avisos do GitHub', () => {
    const md = pageToMarkdown(page(), [])
    expect(md).toContain('# Grande\n\n## Médio\n\n### Pequeno')
    expect(md).toContain('- Grande\n  - Médio\n    - Pequeno')
    expect(md).toContain('- um **forte**\n  - filho\n1. primeiro\n2. segundo\n\nfim')
    expect(md).toContain('[Meu <site>](https://exemplo.com/a?x=1&y=2)')
    expect(md).toContain('> [!WARNING]\n> cuidado')
    expect(md).toContain('> [!TIP]\n> ok')
    expect(md).toContain('> [!NOTE]\n> nota')
  })

  it('texto simples: marcadores, números, sumário e link com o endereço entre parênteses', () => {
    const txt = pageToText(page(), [])
    expect(txt).toContain('• um **forte**\n  • filho\n1. primeiro\n2. segundo')
    expect(txt).toContain('Grande\n  Médio\n    Pequeno')
    expect(txt).toContain('Meu <site> (https://exemplo.com/a?x=1&y=2)')
    expect(txt).toContain('Atenção: cuidado')
    expect(txt).toContain('Sucesso: ok')
    expect(txt).toContain('Nota: nota')
  })

  it('html: h1 a h3, uma lista só para itens vizinhos, número guardado, tom na classe e tudo escapado', () => {
    const html = pageToHtml(page(), [])
    expect(html).toContain('<h1>Grande</h1>')
    expect(html).toContain('<h2>Médio</h2>')
    expect(html).toContain('<h3>Pequeno</h3>')
    expect(html).toMatch(/<ul><li style="margin-left:0em">um <strong>forte<\/strong><\/li>\n<li style="margin-left:1.5em">filho<\/li><\/ul>/)
    expect(html).toMatch(/<ol><li value="1"[^>]*>primeiro<\/li>\n<li value="2"[^>]*>segundo<\/li><\/ol>/)
    expect(html).toContain('<aside class="callout warning">cuidado</aside>')
    expect(html).toContain('<a href="https://exemplo.com/a?x=1&amp;y=2" rel="noopener noreferrer">Meu &lt;site&gt;</a>')
    expect(html).toContain('<nav><ul>')
    expect(html).not.toContain('<site>')
  })

  it('JSON leva os campos novos como estão', () => {
    const json = JSON.parse(pageToJson(page(), []))
    expect(json.blocks.find((b: { id: string }) => b.id === 'a')).toMatchObject({ level: 1 })
    expect(json.blocks.find((b: { id: string }) => b.id === 'k')).toMatchObject({ tone: 'warning' })
    expect(json.blocks.find((b: { id: string }) => b.id === 'j')).toMatchObject({ url: 'https://exemplo.com/a?x=1&y=2' })
  })

  it('um link ainda sem endereço e um sumário sem títulos não deixam rastro nem quebram', () => {
    const w = sampleWorkspace()
    const p = w.page('p5')!
    p.content = [{ id: 'a', type: 'bookmark', url: '', title: '' }, { id: 'b', type: 'toc' }, { id: 'c', type: 'paragraph', text: 'fim' }]
    expect(pageToMarkdown(p, [])).toContain('fim')
    expect(() => pageToHtml(p, [])).not.toThrow()
    expect(() => pageToText(p, [])).not.toThrow()
  })
})

describe('exportação: vídeo, áudio, PDF e link para página', () => {
  const page = (): NotePage => {
    const w = sampleWorkspace()
    const p = w.page('p5')!
    p.title = 'Teste'
    p.content = [
      { id: 'a', type: 'video', url: 'https://exemplo.com/aula.mp4?x=1&y=2', title: 'Aula <1>' },
      { id: 'b', type: 'audio', url: 'https://exemplo.com/som.mp3', title: '' },
      { id: 'c', type: 'pdf', url: 'https://exemplo.com/doc.pdf', title: 'Manual' },
      { id: 'd', type: 'pagelink', pageId: 'p0', title: 'Rotina <x>' },
      { id: 'e', type: 'pagelink', pageId: '', title: '' },
      { id: 'f', type: 'video', url: '', title: '' },
    ]
    return p
  }

  it('markdown: tudo vira um link; texto simples: título e endereço; o link de página aponta para /notes/', () => {
    const md = pageToMarkdown(page(), [])
    expect(md).toContain('[Aula <1>](https://exemplo.com/aula.mp4?x=1&y=2)')
    expect(md).toContain('[https://exemplo.com/som.mp3](https://exemplo.com/som.mp3)')
    expect(md).toContain('[Manual](https://exemplo.com/doc.pdf)')
    expect(md).toContain('[Rotina <x>](/notes/p0)')
    const txt = pageToText(page(), [])
    expect(txt).toContain('Manual (https://exemplo.com/doc.pdf)')
    expect(txt).toContain('→ Rotina <x>')
  })

  it('html: player sem carregar nada sozinho, tudo escapado, e blocos vazios não deixam rastro', () => {
    const html = pageToHtml(page(), [])
    expect(html).toContain('<video controls preload="none" src="https://exemplo.com/aula.mp4?x=1&amp;y=2"></video><p>Aula &lt;1&gt;</p>')
    expect(html).toContain('<audio controls preload="none" src="https://exemplo.com/som.mp3"></audio>')
    expect(html).toContain('<a href="https://exemplo.com/doc.pdf" rel="noopener noreferrer">Manual</a>')
    expect(html).toContain('<a href="/notes/p0">Rotina &lt;x&gt;</a>')
    expect(html).not.toContain('<x>')
    expect(html).not.toContain('<video controls preload="none" src=""')
  })

  it('JSON leva os campos como estão', () => {
    const json = JSON.parse(pageToJson(page(), []))
    expect(json.blocks.find((b: { id: string }) => b.id === 'd')).toMatchObject({ pageId: 'p0', title: 'Rotina <x>' })
    expect(json.blocks.find((b: { id: string }) => b.id === 'a')).toMatchObject({ type: 'video', url: 'https://exemplo.com/aula.mp4?x=1&y=2' })
  })
})

