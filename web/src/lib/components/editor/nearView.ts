// Tells a block whether it is near the screen. A page can hold hundreds of text blocks and a <textarea> costs about
// ten times the memory of a plain <div>, so the ones far from the screen are drawn as text and only the ones near it
// (and the one being edited) are fields. Without IntersectionObserver (old browsers, tests) every block is a field.

const callbacks = new WeakMap<Element, (near: boolean) => void>()
let observer: IntersectionObserver | null | undefined

function shared(): IntersectionObserver | null {
  if (observer !== undefined) return observer
  observer =
    typeof IntersectionObserver === 'undefined'
      ? null
      : new IntersectionObserver(
          (entries) => {
            for (const entry of entries) callbacks.get(entry.target)?.(entry.isIntersecting)
          },
          // a screen and a bit above and below: scrolling never shows a block that has not become a field yet
          { rootMargin: '1200px 0px' },
        )
  return observer
}

export const canObserve = () => shared() !== null

export function nearView(node: HTMLElement, callback: (near: boolean) => void) {
  const io = shared()
  callbacks.set(node, callback)
  io?.observe(node)
  return {
    update(next: (near: boolean) => void) {
      callbacks.set(node, next)
    },
    destroy() {
      io?.unobserve(node)
      callbacks.delete(node)
    },
  }
}

/** For tests: forget the shared observer so a stub installed afterwards is the one used. */
export function resetNearView() {
  observer = undefined
}
