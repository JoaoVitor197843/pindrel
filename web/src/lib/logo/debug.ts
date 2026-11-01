import { LOGO_THEMES, type LogoTheme } from './season'

/**
 * Debug only: `?logo=<theme>` in the URL forces a theme, since otherwise each one shows once a year.
 * Kept in its own file so the release branch can ship it as a stub that always returns undefined.
 */
export function forcedTheme(search: string): LogoTheme | undefined {
  const forced = new URLSearchParams(search).get('logo')
  return LOGO_THEMES.find((t) => t === forced)
}
