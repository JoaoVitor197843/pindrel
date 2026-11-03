const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])'

function focusables(node: HTMLElement): HTMLElement[] {
  // `hidden`/`inert` ancestors take things out of the tab order; jsdom has no layout, so only those are looked at
  return [...node.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => !el.closest('[hidden],[inert]'))
}

/**
 * For a modal dialog: Tab and Shift+Tab go around inside it (a keyboard user can never end up behind it, which is what
 * `aria-modal` promises), and when it goes away the focus returns to whatever had it when it opened.
 */
export function modal(node: HTMLElement, from?: Element | null) {
  // children's actions (a field taking the focus) run before this one: whoever opens the dialog passes who had it before
  const opener = from instanceof HTMLElement ? from : document.activeElement instanceof HTMLElement ? document.activeElement : null
  if (!node.hasAttribute('tabindex')) node.tabIndex = -1
  // the dialog opens with the focus inside it, unless it already put it somewhere itself (the safe button, a field)
  if (!node.contains(document.activeElement)) (focusables(node)[0] ?? node).focus()

  function onkeydown(e: KeyboardEvent) {
    if (e.key !== 'Tab' || e.defaultPrevented) return
    const items = focusables(node)
    if (items.length === 0) {
      e.preventDefault()
      node.focus()
      return
    }
    const first = items[0]
    const last = items[items.length - 1]
    const active = document.activeElement
    const inside = !!active && node.contains(active)
    if (e.shiftKey && (!inside || active === first || active === node)) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && (!inside || active === last)) {
      e.preventDefault()
      first.focus()
    }
  }

  document.addEventListener('keydown', onkeydown)
  return {
    destroy() {
      document.removeEventListener('keydown', onkeydown)
      if (opener?.isConnected) opener.focus()
    },
  }
}
