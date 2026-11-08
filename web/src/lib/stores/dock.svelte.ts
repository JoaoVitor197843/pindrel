// A side panel that is docked beside the page on a wide screen (open at first, the choice remembered) and a drawer that
// always starts closed on a narrow one: a choice made on a big screen must not cover the page on a phone.

export class Dock {
  readonly key: string
  /** The remembered choice on a wide screen; null until the person makes one. */
  choice = $state<boolean | null>(null)
  drawer = $state(false)

  constructor(key: string) {
    this.key = key
    try {
      const stored = localStorage.getItem(key)
      this.choice = stored === '1' ? true : stored === '0' ? false : null
    } catch {
      // storage blocked: no choice remembered
    }
  }

  isOpen(wide: boolean): boolean {
    return wide ? (this.choice ?? true) : this.drawer
  }

  toggle(wide: boolean) {
    if (!wide) {
      this.drawer = !this.drawer
      return
    }
    this.choice = !this.isOpen(true)
    try {
      localStorage.setItem(this.key, this.choice ? '1' : '0')
    } catch {
      // not remembered: it still works for this visit
    }
  }

  /** Shuts the drawer (a no-op beside the page, where the panel is not a drawer). */
  closeDrawer() {
    this.drawer = false
  }
}

/** The docks beside the page: their width without the zoom (the rail with the arrow, and the panel). */
export const RAIL_WIDTH = 48
export const DOCK_PANEL_WIDTH = 240
/** The page column (max-w-3xl); everything left over on either side is room for a dock. */
const PAGE_WIDTH = 768
const WIDE_BREAKPOINT = 1340

/**
 * How much the docks grow: 1 at the wide breakpoint, more on bigger screens so the panels use the room beside the page
 * instead of sitting small in it, up to 1.7. They take about 80% of the room that is left on each side.
 */
export function dockScale(viewportWidth: number): number {
  if (!Number.isFinite(viewportWidth) || viewportWidth < WIDE_BREAKPOINT) return 1
  const room = (viewportWidth - PAGE_WIDTH) / 2
  const scale = (room * 0.8) / (RAIL_WIDTH + DOCK_PANEL_WIDTH)
  return Math.floor(Math.min(1.7, Math.max(1, scale)) * 100) / 100
}
