import { describe, expect, it } from 'vitest'
import { inlineCssAndPrecompress } from './vite.assets.ts'

type Handler = (html: string, ctx: { bundle?: Record<string, unknown> }) => string
const handler = (inlineCssAndPrecompress().transformIndexHtml as unknown as { handler: Handler }).handler
const link = '<link rel="stylesheet" crossorigin href="/assets/a.css">'

describe('inlineCssAndPrecompress', () => {
  it('põe o CSS dentro do HTML e tira o arquivo do pacote', () => {
    const bundle: Record<string, unknown> = { 'assets/a.css': { type: 'asset', source: 'body{color:red}' } }
    const out = handler(`<head>${link}</head>`, { bundle })
    expect(out).toBe('<head><style>body{color:red}</style></head>')
    expect(bundle['assets/a.css']).toBeUndefined()
  })

  it('não mexe em CSS que fecharia a tag <style> antes da hora', () => {
    const bundle: Record<string, unknown> = { 'assets/a.css': { type: 'asset', source: 'a{content:"</style><script>x"}' } }
    expect(handler(`<head>${link}</head>`, { bundle })).toContain(link)
    expect(bundle['assets/a.css']).toBeDefined()
  })

  it('link que não está no pacote, ou sem pacote, fica como está', () => {
    expect(handler(`<head>${link}</head>`, { bundle: {} })).toContain(link)
    expect(handler(`<head>${link}</head>`, {})).toContain(link)
  })

  it('só troca folhas de estilo: outras tags e vários links', () => {
    const bundle: Record<string, unknown> = {
      'assets/a.css': { type: 'asset', source: 'a{}' },
      'assets/b.css': { type: 'asset', source: 'b{}' },
    }
    const html = `${link}<link rel="icon" href="/favicon.svg"><link rel="stylesheet" href="/assets/b.css">`
    expect(handler(html, { bundle })).toBe('<style>a{}</style><link rel="icon" href="/favicon.svg"><style>b{}</style>')
  })
})
