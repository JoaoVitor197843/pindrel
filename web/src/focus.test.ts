import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const css = readFileSync('src/app.css', 'utf8')

describe('focus ring', () => {
  it('is drawn for the keyboard with the accent colour, off the edge of the element', () => {
    expect(css).toMatch(/:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--color-accent-line\)[^}]*outline-offset:\s*2px/)
  })

  it('has rounded corners around a text block, not the square ones of a plain field', () => {
    const rule = css.match(/([^{}]*:focus-visible[^{}]*)\{\s*border-radius:\s*var\(--radius-field\);?\s*\}/)
    expect(rule).not.toBeNull()
    for (const selector of ['textarea', 'input', '[data-nav]', '[data-rich]']) expect(rule![1]).toContain(`${selector}:focus-visible`)
  })

  it('the rounded corner is the app\'s own field radius, which exists', () => {
    expect(css).toMatch(/--radius-field:\s*10px/)
  })
})
