import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { stubLocalStorage } from '../../test/storage'
import { AuthApiError, type Account, type AuthApi, type Tokens } from '../api/auth'
import { Auth } from './auth.svelte'
import { session } from './files.svelte'

const user: Account = { id: '11111111-1111-1111-1111-111111111111', email: 'a@b.co', username: 'ana' }
const tok = (n: number, expiresIn = 900): Tokens => ({ accessToken: `tok.en.${n}`, expiresIn })

/** An API that answers from a script, so nothing depends on timing of a real network. */
function fakeApi(over: Partial<Record<keyof AuthApi, unknown>> = {}) {
  let n = 0
  const defaults = {
    login: vi.fn(async (): Promise<Tokens> => tok(++n)),
    refresh: vi.fn(async (): Promise<Tokens> => tok(++n)),
    me: vi.fn(async () => user),
    register: vi.fn(async () => user),
    logout: vi.fn(async (): Promise<void> => {}),
  }
  return { ...defaults, ...over } as typeof defaults
}

const make = (api: unknown) => new Auth(api as AuthApi)

let data: Map<string, string>
beforeEach(() => {
  data = stubLocalStorage()
  session.token = null
  vi.useFakeTimers()
})
afterEach(() => vi.useRealTimers())

describe('Auth', () => {
  it('login keeps the token in memory (and for the file service), remembers the device and names the user', async () => {
    const api = fakeApi()
    const auth = make(api)
    expect(auth.status).toBe('out')
    expect(await auth.login('a@b.co', 'senha-forte', true)).toEqual(user)
    expect(auth.status).toBe('in')
    expect(auth.user).toEqual(user)
    expect(session.token).toBe('tok.en.1')
    expect(auth.remembered).toBe(true)
    expect(api.login).toHaveBeenCalledWith('a@b.co', 'senha-forte', false)
    // the token is not written to any storage
    expect(JSON.stringify([...data])).not.toContain('tok.en')
    expect(JSON.stringify(Object.keys(sessionStorage ?? {}))).not.toContain('tok.en')
  })

  it('"manter conectado" off asks for a session-only cookie', async () => {
    const api = fakeApi()
    await make(api).login('a@b.co', 'senha-forte', false)
    expect(api.login).toHaveBeenCalledWith('a@b.co', 'senha-forte', true)
  })

  it('a failed login leaves nobody signed in and nothing remembered', async () => {
    const api = fakeApi({ login: vi.fn(async () => Promise.reject(new AuthApiError(401, 'invalid_credentials'))) })
    const auth = make(api)
    await expect(auth.login('a@b.co', 'errada-demais', true)).rejects.toMatchObject({ code: 'invalid_credentials' })
    expect(auth.status).toBe('out')
    expect(session.token).toBeNull()
    expect(auth.remembered).toBe(false)
  })

  it('register creates the account without signing in', async () => {
    const api = fakeApi()
    const auth = make(api)
    expect(await auth.register('a@b.co', 'ana', 'senha-forte')).toEqual(user)
    expect(auth.status).toBe('out')
    expect(api.login).not.toHaveBeenCalled()
  })

  it('renews the token before it runs out, and keeps doing it', async () => {
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    await vi.advanceTimersByTimeAsync(719_000)
    expect(api.refresh).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(2_000)
    expect(api.refresh).toHaveBeenCalledTimes(1)
    expect(session.token).toBe('tok.en.2')
    await vi.advanceTimersByTimeAsync(721_000)
    expect(api.refresh).toHaveBeenCalledTimes(2)
    expect(session.token).toBe('tok.en.3')
    expect(auth.status).toBe('in')
  })

  it('a refusal while renewing signs the device out and forgets it', async () => {
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    api.refresh.mockRejectedValueOnce(new AuthApiError(401, 'invalid_refresh_token'))
    await vi.advanceTimersByTimeAsync(721_000)
    expect(auth.status).toBe('out')
    expect(auth.user).toBeNull()
    expect(session.token).toBeNull()
    expect(auth.remembered).toBe(false)
  })

  it('no network while renewing keeps the session and tries again in 30 s', async () => {
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    api.refresh.mockRejectedValueOnce(new AuthApiError(0, 'network'))
    await vi.advanceTimersByTimeAsync(721_000)
    expect(auth.status).toBe('in')
    expect(session.token).toBe('tok.en.1')
    await vi.advanceTimersByTimeAsync(30_000)
    expect(api.refresh).toHaveBeenCalledTimes(2)
    expect(session.token).toBe('tok.en.2')
  })

  it('a busy server that says "wait 45 s" is not asked sooner', async () => {
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    api.refresh.mockRejectedValueOnce(new AuthApiError(503, 'server_busy', 45_000))
    await vi.advanceTimersByTimeAsync(721_000)
    await vi.advanceTimersByTimeAsync(40_000)
    expect(api.refresh).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(6_000)
    expect(api.refresh).toHaveBeenCalledTimes(2)
  })

  it('a token with a very short life is not renewed in a tight loop', async () => {
    const api = fakeApi({ login: vi.fn(async () => tok(1, 1)), refresh: vi.fn(async () => tok(2, 1)) })
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    await vi.advanceTimersByTimeAsync(4_000)
    expect(api.refresh).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(2_000)
    expect(api.refresh).toHaveBeenCalledTimes(1)
  })

  it('coming back to a hidden tab renews at once when the token ran out meanwhile', async () => {
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    // the browser froze the timers; the clock moved on
    vi.setSystemTime(Date.now() + 20 * 60_000)
    document.dispatchEvent(new Event('visibilitychange'))
    await vi.advanceTimersByTimeAsync(0)
    expect(api.refresh).toHaveBeenCalledTimes(1)
    expect(auth).toBeTruthy()
  })

  it('logout signs out here at once, tells the server, and survives the server being unreachable', async () => {
    const api = fakeApi({ logout: vi.fn(async () => Promise.reject(new AuthApiError(0, 'network'))) })
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    await auth.logout()
    expect(api.logout).toHaveBeenCalledWith('tok.en.1')
    expect(auth.status).toBe('out')
    expect(auth.user).toBeNull()
    expect(session.token).toBeNull()
    expect(auth.remembered).toBe(false)
    // and nothing is renewed afterwards
    await vi.advanceTimersByTimeAsync(2_000_000)
    expect(api.refresh).not.toHaveBeenCalled()
  })

  it('an answer that arrives after logout cannot bring the session back', async () => {
    let release!: (t: Tokens) => void
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    api.refresh.mockImplementationOnce(() => new Promise<Tokens>((r) => (release = r)))
    await vi.advanceTimersByTimeAsync(721_000)
    await auth.logout()
    release(tok(99))
    await vi.advanceTimersByTimeAsync(0)
    expect(auth.status).toBe('out')
    expect(session.token).toBeNull()
  })

  it('a login that finishes after a logout is dropped too', async () => {
    let release!: (t: Tokens) => void
    const api = fakeApi({ login: vi.fn(() => new Promise<Tokens>((r) => (release = r))) })
    const auth = make(api)
    const pending = auth.login('a@b.co', 'senha-forte', true).catch((e) => e)
    await auth.logout()
    release(tok(5))
    expect(await pending).toMatchObject({ code: 'cancelled' })
    expect(auth.status).toBe('out')
    expect(session.token).toBeNull()
  })

  it('restore turns the cookie back into a session, but only on a device that had one', async () => {
    const api = fakeApi()
    expect(await make(api).restore()).toBe(false)
    expect(api.refresh).not.toHaveBeenCalled()

    data.set('pindrel:account', '1')
    const auth = make(api)
    const done = auth.restore()
    expect(auth.status).toBe('checking')
    expect(await done).toBe(true)
    expect(auth.status).toBe('in')
    expect(auth.user).toEqual(user)
    expect(session.token).toBe('tok.en.1')
  })

  it('restore with a cookie that is gone forgets the device; with the network down it keeps the note', async () => {
    data.set('pindrel:account', '1')
    const gone = make(fakeApi({ refresh: vi.fn(async () => Promise.reject(new AuthApiError(401, 'invalid_refresh_token'))) }))
    expect(await gone.restore()).toBe(false)
    expect(gone.status).toBe('out')
    expect(gone.remembered).toBe(false)

    data.set('pindrel:account', '1')
    const offline = make(fakeApi({ refresh: vi.fn(async () => Promise.reject(new AuthApiError(0, 'network'))) }))
    expect(await offline.restore()).toBe(false)
    expect(offline.status).toBe('out')
    expect(offline.remembered).toBe(true)
  })

  it('call runs with the token; a 401 renews once and retries once; a second 401 is the caller\'s', async () => {
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)

    expect(await auth.call(async (t) => t)).toBe('tok.en.1')

    const flaky = vi.fn(async (t: string) => {
      if (t === 'tok.en.1') throw new AuthApiError(401, 'unauthorized')
      return `ok ${t}`
    })
    expect(await auth.call(flaky)).toBe('ok tok.en.2')
    expect(flaky).toHaveBeenCalledTimes(2)

    const always = vi.fn(async () => Promise.reject(new AuthApiError(401, 'unauthorized')))
    await expect(auth.call(always)).rejects.toMatchObject({ status: 401 })
    expect(always).toHaveBeenCalledTimes(2)

    const other = vi.fn(async () => Promise.reject(new AuthApiError(500, 'internal_error')))
    await expect(auth.call(other)).rejects.toMatchObject({ status: 500 })
    expect(other).toHaveBeenCalledTimes(1)
  })

  it('call with nobody signed in does not touch the network', async () => {
    const api = fakeApi()
    await expect(make(api).call(async () => 1)).rejects.toMatchObject({ code: 'not_signed_in' })
    expect(api.refresh).not.toHaveBeenCalled()
  })

  it('five requests refused at once share one renewal', async () => {
    const api = fakeApi()
    const auth = make(api)
    await auth.login('a@b.co', 'senha-forte', true)
    const run = async (t: string) => {
      if (t === 'tok.en.1') throw new AuthApiError(401, 'unauthorized')
      return t
    }
    const all = await Promise.all([1, 2, 3, 4, 5].map(() => auth.call(run)))
    expect(all).toEqual(Array(5).fill('tok.en.2'))
    expect(api.refresh).toHaveBeenCalledTimes(1)
  })

  it('storage that refuses to work does not break signing in', async () => {
    vi.stubGlobal('localStorage', {
      getItem: () => {
        throw new DOMException('blocked', 'SecurityError')
      },
      setItem: () => {
        throw new DOMException('blocked', 'SecurityError')
      },
      removeItem: () => {
        throw new DOMException('blocked', 'SecurityError')
      },
    })
    const auth = make(fakeApi())
    await expect(auth.login('a@b.co', 'senha-forte', true)).resolves.toEqual(user)
    expect(auth.status).toBe('in')
  })
})
