// Regenerates web_inline_cases.json from the web's own reader and writer (the reference the Dart port is tested against).
// node needs to resolve extensionless .ts imports, e.g. with a small resolve hook:  node --experimental-strip-types --import hook gen_web_inline_cases.mjs web_inline_cases.json
import { parseInline, mergeRuns } from '../../../../../../web/src/lib/stores/inlineParse.ts'
import { serializeRuns } from '../../../../../../web/src/lib/components/editor/rich/runs.ts'
import fs from 'node:fs'
let seed = 12345
const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296
const atoms = ['**', '*', '__', '_', '~~', '==', '`', '[', ']', '(', ')', 'https://a.b', ' ', ' ', 'a', 'bc', 'x_y', '\n', 'é', '1', '[t](https://x.org)', '`c`', 'mailto:a@b.c']
const cases = []
for (let i = 0; i < 600; i++) {
  let s = ''
  const n = 1 + Math.floor(rnd() * 14)
  for (let k = 0; k < n; k++) s += atoms[Math.floor(rnd() * atoms.length)]
  const runs = parseInline(s)
  const m = (r) => ['bold','italic','underline','strike','highlight','code'].filter(k => r.marks[k]).concat(r.marks.link ? ['link='+r.marks.link] : []).join(',')
  cases.push({ s, runs: runs.map(r => r.text + '|' + m(r)), out: serializeRuns(runs) })
}
fs.writeFileSync(process.argv[2], JSON.stringify(cases))
