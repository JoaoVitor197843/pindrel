import { vi } from 'vitest'

/** A working `localStorage`: the one of the test environment is not always usable. Returns the backing map. */
export function stubLocalStorage(): Map<string, string> {
  const data = new Map<string, string>()
  vi.stubGlobal('localStorage', {
    getItem: (k: string) => data.get(k) ?? null,
    setItem: (k: string, v: string) => void data.set(k, String(v)),
    removeItem: (k: string) => void data.delete(k),
    clear: () => data.clear(),
  })
  return data
}
