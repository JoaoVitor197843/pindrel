/** Grows a textarea with its text (no scrollbar, no fixed rows): the height follows the content. */
export function autosize(node: HTMLTextAreaElement, _value?: unknown) {
  const fit = () => {
    node.style.height = 'auto'
    node.style.height = `${node.scrollHeight}px`
  }
  fit()
  node.addEventListener('input', fit)
  window.addEventListener('resize', fit)
  return {
    update: fit,
    destroy() {
      node.removeEventListener('input', fit)
      window.removeEventListener('resize', fit)
    },
  }
}

/** Puts the caret at the start or the end of a field and focuses it. */
export function place(el: HTMLElement | null | undefined, where: 'start' | 'end' = 'end') {
  if (!el) return
  // a formatted block is drawn as plain markup until focused: it reads where the caret goes once it becomes a field
  el.dataset.caret = where
  el.focus()
  if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement)) return
  const at = where === 'end' ? el.value.length : 0
  try {
    el.setSelectionRange(at, at)
  } catch {
    // some input types have no selection: the focus is enough
  }
}
