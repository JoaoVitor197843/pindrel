import { afterEach, beforeEach, vi } from 'vitest'

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
  return min ? viewport.width >= Number(min[1]) : false
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

// No server behind it: the gateway "does not exist" (404) unless the test swaps fetch.
const noGateway = async () => new Response(null, { status: 404 })
vi.stubGlobal('fetch', vi.fn(noGateway))
beforeEach(() => {
  vi.mocked(fetch).mockReset().mockImplementation(noGateway)
})
