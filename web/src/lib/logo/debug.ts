import type { LogoTheme } from './season'

/** Release build: no way to force a theme from the URL; the theme is always the one of the day. */
export function forcedTheme(_search: string): LogoTheme | undefined {
  return undefined
}
