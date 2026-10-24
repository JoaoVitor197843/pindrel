import { forcedTheme } from './debug'

export type LogoTheme =
  | 'normal'
  | 'halloween'
  | 'd24'
  | 'd25'
  | 'd31'
  | 'd1'
  | 'carnaval'
  | 'pascoa'
  | 'namorados'
  | 'junino'
  | 'dev'

export const LOGO_THEMES: readonly LogoTheme[] = [
  'normal',
  'halloween',
  'd24',
  'd25',
  'd31',
  'd1',
  'carnaval',
  'pascoa',
  'namorados',
  'junino',
  'dev',
]

/** Easter Sunday (Meeus/Jones/Butcher, Gregorian calendar), at local midnight. */
export function easter(year: number): Date {
  const a = year % 19
  const b = Math.floor(year / 100)
  const c = year % 100
  const d = Math.floor(b / 4)
  const e = b % 4
  const f = Math.floor((b + 8) / 25)
  const g = Math.floor((b - f + 1) / 3)
  const h = (19 * a + b - d - g + 15) % 30
  const i = Math.floor(c / 4)
  const k = c % 4
  const l = (32 + 2 * e + 2 * i - h - k) % 7
  const m = Math.floor((a + 11 * h + 22 * l) / 451)
  const month = Math.floor((h + l - 7 * m + 114) / 31)
  const day = ((h + l - 7 * m + 114) % 31) + 1
  return new Date(year, month - 1, day)
}

function addDays(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
}

function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

/** 1-based day of the year, counted on local calendar days (so a DST change cannot shift it). */
function dayOfYear(d: Date): number {
  const start = Date.UTC(d.getFullYear(), 0, 0)
  return Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - start) / 86_400_000)
}

/** A region's own dates: returns the theme of that day, or null to fall through to the global table. */
export type RegionalRule = (d: Date) => LogoTheme | null

/**
 * Rules by region (ISO 3166-1 alpha-2, upper case, e.g. 'BR'). Empty for now: add a region here and it is
 * consulted before the global table, so a regional date wins over a global one on the same day.
 */
export const regionalRules: Record<string, RegionalRule[]> = {}

/** Theme of the logo for a local date (and an optional region); the first match wins. */
export function seasonalTheme(
  d: Date,
  region?: string | null,
  rules: Record<string, RegionalRule[]> = regionalRules,
): LogoTheme {
  for (const rule of rules[region?.toUpperCase() ?? ''] ?? []) {
    const theme = rule(d)
    if (theme) return theme
  }
  const m = d.getMonth() + 1
  const day = d.getDate()
  if (m === 10 && day === 31) return 'halloween'
  if (m === 12 && day === 24) return 'd24'
  if (m === 12 && day === 25) return 'd25'
  if (m === 12 && day === 31) return 'd31'
  if (m === 1 && day === 1) return 'd1'
  if (m === 6 && day === 12) return 'namorados'
  if (m === 6 && day === 24) return 'junino'
  if (dayOfYear(d) === 256) return 'dev'
  const e = easter(d.getFullYear())
  for (let k = -2; k <= 0; k++) if (sameDay(d, addDays(e, k))) return 'pascoa'
  for (let k = -50; k <= -47; k++) if (sameDay(d, addDays(e, k))) return 'carnaval'
  return 'normal'
}

/**
 * Theme to play: a debug-forced one (see `debug.ts`) or the one of the device's local date.
 */
export function currentTheme(
  now: Date = new Date(),
  search: string = globalThis.location?.search ?? '',
  region?: string | null,
): LogoTheme {
  return forcedTheme(search) ?? seasonalTheme(now, region)
}
