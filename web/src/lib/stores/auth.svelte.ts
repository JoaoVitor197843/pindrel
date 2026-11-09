import { AuthApi, AuthApiError, type Account } from '../api/auth'
import { session } from './files.svelte'

export type AuthStatus = 'checking' | 'out' | 'in'

const HINT_KEY = 'pindrel:account'
/** The access token is renewed after this share of its life, so a slow answer never leaves a request without one. */
const RENEW_AT = 0.8
const MIN_RENEW_MS = 5_000
/** After a failed renewal that was not a refusal (no network, a busy server) the token is still good for a while: try again. */
const RETRY_MS = 30_000

// The only thing kept in the browser is a note that this device has a session, so a reload knows to ask for one; the
// secrets are the access token (this file's memory, never storage) and the refresh cookie (HttpOnly, out of reach of scripts).
const hint = {
  has(): boolean {
    try {
      return localStorage.getItem(HINT_KEY) === '1'
    } catch {
      return false
    }
  },
  set() {
    try {
      localStorage.setItem(HINT_KEY, '1')
    } catch {
      // storage blocked: the session lives until the page closes
    }
  },
  clear() {
    try {
      localStorage.removeItem(HINT_KEY)
    } catch {
      // nothing to clear
    }
  },
}

/** Who is signed in on this page. The access token lives here, in memory, and the refresh token is a cookie. */
export class Auth {
  status = $state<AuthStatus>('out')
  user = $state<Account | null>(null)
  readonly #api: AuthApi
  #token: string | null = null
  #expiresAt = 0
  #timer: ReturnType<typeof setTimeout> | undefined
  #renewing: Promise<boolean> | null = null
  /** Bumped by every sign-out, so an answer that arrives after it cannot bring the session back. */
  #epoch = 0

  constructor(api: AuthApi = new AuthApi()) {
    this.#api = api
    // a hidden tab's timers are throttled: come back and renew at once if the token ran out meanwhile
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && this.status === 'in' && Date.now() >= this.#expiresAt - 10_000) void this.#renew()
      })
    }
  }

  /** This device was signed in before (the cookie may still be good). */
  get remembered(): boolean {
    return hint.has()
  }

  #adopt(token: string, expiresIn: number) {
    this.#token = token
    session.token = token
    this.#expiresAt = Date.now() + expiresIn * 1000
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => void this.#renew(), Math.max(MIN_RENEW_MS, expiresIn * 1000 * RENEW_AT))
  }

  #signOutLocal() {
    this.#epoch++
    clearTimeout(this.#timer)
    this.#token = null
    session.token = null
    this.user = null
    this.status = 'out'
    hint.clear()
  }

  /** Asks for a new access token; false when it could not be had. Several callers share one request. */
  #renew(): Promise<boolean> {
    this.#renewing ??= (async () => {
      const epoch = this.#epoch
      try {
        const t = await this.#api.refresh()
        if (epoch !== this.#epoch) return false
        this.#adopt(t.accessToken, t.expiresIn)
        return true
      } catch (e) {
        if (epoch !== this.#epoch) return false
        if (e instanceof AuthApiError && (e.status === 401 || e.status === 403)) this.#signOutLocal()
        else {
          // not a refusal: keep what there is and try again soon
          clearTimeout(this.#timer)
          this.#timer = setTimeout(() => void this.#renew(), Math.max(RETRY_MS, e instanceof AuthApiError ? e.retryAfterMs : 0))
        }
        return false
      } finally {
        this.#renewing = null
      }
    })()
    return this.#renewing
  }

  /** On page load: turns the refresh cookie back into a session, if this device had one. */
  async restore(): Promise<boolean> {
    if (!hint.has()) return false
    this.status = 'checking'
    const epoch = this.#epoch
    try {
      const t = await this.#api.refresh()
      const user = await this.#api.me(t.accessToken)
      if (epoch !== this.#epoch) return false
      this.#adopt(t.accessToken, t.expiresIn)
      this.user = user
      this.status = 'in'
      return true
    } catch (e) {
      // a refusal means the cookie is gone or revoked; anything else may pass, so the note stays
      if (e instanceof AuthApiError && (e.status === 401 || e.status === 403)) hint.clear()
      this.status = 'out'
      return false
    }
  }

  /** Signs in. Throws `AuthApiError`; on success the session is set and the account returned. */
  async login(email: string, password: string, keepSignedIn: boolean): Promise<Account> {
    const epoch = this.#epoch
    const t = await this.#api.login(email, password, !keepSignedIn)
    const user = await this.#api.me(t.accessToken)
    if (epoch !== this.#epoch) throw new AuthApiError(0, 'cancelled')
    this.#adopt(t.accessToken, t.expiresIn)
    this.user = user
    this.status = 'in'
    hint.set()
    return user
  }

  /** Creates the account. It does not sign in: the server only creates it. */
  register(email: string, username: string, password: string): Promise<Account> {
    return this.#api.register(email, username, password)
  }

  /** Ends the session. The device is signed out even when the server cannot be reached. */
  async logout(): Promise<void> {
    const token = this.#token ?? undefined
    this.#signOutLocal()
    try {
      await this.#api.logout(token)
    } catch {
      // the cookie could not be revoked now; it is no longer used by this page
    }
  }

  /** Runs a request with the access token; one refusal renews the token and tries again, a second one signs out. */
  async call<T>(run: (token: string) => Promise<T>): Promise<T> {
    if (!this.#token) throw new AuthApiError(401, 'not_signed_in')
    try {
      return await run(this.#token)
    } catch (e) {
      if (!(e instanceof AuthApiError) || e.status !== 401) throw e
      if (!(await this.#renew()) || !this.#token) throw e
      return run(this.#token)
    }
  }
}

export const auth = new Auth()
