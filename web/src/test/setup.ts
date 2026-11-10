import { afterEach, beforeEach, vi } from 'vitest'
import { configure } from '@testing-library/dom'

// findBy*/waitFor default to 1 s, which a busy CI runner (four jobs at once) overruns
configure({ asyncUtilTimeout: 8000 })

// jsdom has no ResizeObserver (Svelte's bind:clientHeight needs one): nothing resizes there, so a stub that never fires is exact.
globalThis.ResizeObserver ??= class {
  observe() {}
  unobserve() {}
  disconnect() {}
} as unknown as typeof ResizeObserver

// jsdom does not implement matchMedia; this stub evaluates `min-width` against `viewport.width`.
export const viewport = {
  width: 450,
  listeners: new Set<() => void>(),
  set(width: number) {
    this.width = width
    this.listeners.forEach((notify) => notify())
  },
}

function matches(query: string) {
  const min = /min-width:\s*(\d+)px/.exec(query)
  if (min) return viewport.width >= Number(min[1])
  const max = /max-width:\s*(\d+)px/.exec(query)
  return max ? viewport.width <= Number(max[1]) : false
}

window.matchMedia = (query: string) => {
  const listeners = new Map<EventListenerOrEventListenerObject, () => void>()
  return {
    media: query,
    get matches() {
      return matches(query)
    },
    onchange: null,
    addEventListener(_type: string, listener: EventListenerOrEventListenerObject) {
      const notify = () => typeof listener === 'function' && listener(new Event('change'))
      listeners.set(listener, notify)
      viewport.listeners.add(notify)
    },
    removeEventListener(_type: string, listener: EventListenerOrEventListenerObject) {
      const notify = listeners.get(listener)
      if (notify) viewport.listeners.delete(notify)
      listeners.delete(listener)
    },
    addListener() {},
    removeListener() {},
    dispatchEvent: () => false,
  } as MediaQueryList
}

afterEach(() => viewport.set(450))

// The rich-text editor (ProseMirror) asks ranges and the document for geometry when it scrolls to the caret; jsdom has no
// layout, and Lexical-style paste code names DragEvent and ClipboardEvent, which it lacks too.
{
  const rect = { x: 0, y: 0, top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0, toJSON: () => ({}) }
  Range.prototype.getBoundingClientRect = () => rect as DOMRect
  Range.prototype.getClientRects = () => ({ length: 0, item: () => null, [Symbol.iterator]: function* () {} }) as unknown as DOMRectList
  document.elementFromPoint = () => null
  const g = globalThis as { DragEvent?: unknown; ClipboardEvent?: unknown }
  g.DragEvent ??= class DragEvent extends Event {}
  g.ClipboardEvent ??= class ClipboardEvent extends Event {}
}

// No server behind it: the gateway "does not exist" (404) unless the test swaps fetch.
const noGateway = async () => new Response(null, { status: 404 })
vi.stubGlobal('fetch', vi.fn(noGateway))
beforeEach(() => {
  vi.mocked(fetch).mockReset().mockImplementation(noGateway)
})
