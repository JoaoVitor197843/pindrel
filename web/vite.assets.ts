import { brotliCompressSync, constants, gzipSync } from 'node:zlib'
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { join, relative } from 'node:path'
import type { Plugin } from 'vite'

/**
 * Two build-time changes that make the first load faster on a slow connection, with no runtime cost:
 *  - the stylesheet goes inside index.html: one request less before the first paint (about 300 ms on a 3G profile);
 *  - every text asset gets `.br` and `.gz` siblings, which the Go server hands out as they are
 *    (`spaHandler`), so it never compresses anything at request time (no CPU, no RAM). Disk is the price.
 */
export function inlineCssAndPrecompress(): Plugin {
  let outDir = 'dist'
  return {
    name: 'pindrel-assets',
    apply: 'build',
    configResolved(config) {
      outDir = config.build.outDir
    },
    transformIndexHtml: {
      order: 'post',
      handler(html, ctx) {
        const bundle = ctx.bundle
        if (!bundle) return html
        return html.replace(/<link rel="stylesheet"[^>]*href="\/?([^"]+\.css)"[^>]*>/g, (tag, file: string) => {
          const asset = bundle[file]
          if (!asset || asset.type !== 'asset') return tag
          const css = String(asset.source)
          // a stylesheet that contained this would end the <style> early; none does today, but never trust that silently
          if (/<\/style/i.test(css)) return tag
          delete bundle[file]
          return `<style>${css}</style>`
        })
      },
    },
    closeBundle() {
      const walk = (dir: string): string[] =>
        readdirSync(dir).flatMap((name) => {
          const full = join(dir, name)
          return statSync(full).isDirectory() ? walk(full) : [full]
        })
      writeServiceWorker(outDir, walk)
      for (const file of walk(outDir)) {
        if (!/\.(html|js|css|svg|json|txt|map)$/.test(file)) continue
        const raw = readFileSync(file)
        if (raw.length < 256) continue // a few bytes do not pay for the header
        writeFileSync(`${file}.br`, brotliCompressSync(raw, { params: { [constants.BROTLI_PARAM_QUALITY]: 11 } }))
        writeFileSync(`${file}.gz`, gzipSync(raw, { level: 9 }))
      }
    },
  }
}

/**
 * Writes dist/sw.js from sw.template.js: the files under /assets/ are listed so the worker can keep them all at install
 * (the editor's lazy chunks included), and the version is a hash of that list, so a new build is a new worker.
 */
function writeServiceWorker(outDir: string, walk: (dir: string) => string[]) {
  const assets = walk(join(outDir, 'assets'))
    .map((f) => '/' + relative(outDir, f).split('\\').join('/'))
    .filter((f) => !/\.(br|gz|map)$/.test(f))
    .sort()
  const version = createHash('sha256').update(assets.join('\n')).digest('hex').slice(0, 12)
  const template = readFileSync(new URL('./sw.template.js', import.meta.url), 'utf8')
  writeFileSync(join(outDir, 'sw.js'), template.replace('__VERSION__', version).replace('__ASSETS__', JSON.stringify(assets)))
}
