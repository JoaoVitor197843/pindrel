import { ErrorHttp, LoginInput, LoginRefreshResponse, RegisterInput, RegisterResponse, UserSummary } from '../../types/shared/protos/auth'

/** An answer bigger than this is not from a Pindrel server: it is discarded without decoding. */
const MAX_REPLY = 64 * 1024
const TIMEOUT_MS = 15_000

/** What went wrong, in the server's own words (`code`), or `network` / `timeout` / `bad_reply` when nothing sensible came back. */
export class AuthApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    /** Milliseconds the server asked to wait (`Retry-After`), 0 when it did not. */
    readonly retryAfterMs = 0,
  ) {
    super(`${status} ${code}`)
  }
}

export interface Tokens {
  accessToken: string
  /** Seconds the access token lives. */
  expiresIn: number
}

export interface Account {
  id: string
  email: string
  username: string
}

type Fetch = typeof fetch

/**
 * The auth routes of the server the page came from. The access token travels in the body and is the caller's to keep (in
 * memory only); the refresh token is an HttpOnly cookie that the browser sends by itself, so nothing here ever sees it.
 */
export class AuthApi {
  readonly #fetch: Fetch

  constructor(f?: Fetch) {
    this.#fetch = f ?? ((...args) => globalThis.fetch(...args))
  }

  async #call(method: 'GET' | 'POST', path: string, init: { body?: Uint8Array; token?: string; signal?: AbortSignal } = {}): Promise<Uint8Array> {
    const headers: Record<string, string> = { Accept: 'application/x-protobuf' }
    if (init.body) headers['Content-Type'] = 'application/x-protobuf'
    if (init.token) headers.Authorization = `Bearer ${init.token}`

    const timeout = new AbortController()
    const timer = setTimeout(() => timeout.abort(), TIMEOUT_MS)
    const onAbort = () => timeout.abort()
    init.signal?.addEventListener('abort', onAbort)
    let res: Response
    try {
      res = await this.#fetch(path, { method, headers, body: init.body as BodyInit | undefined, signal: timeout.signal, credentials: 'same-origin' })
    } catch (e) {
      if (init.signal?.aborted) throw e
      throw new AuthApiError(0, timeout.signal.aborted ? 'timeout' : 'network')
    } finally {
      clearTimeout(timer)
      init.signal?.removeEventListener('abort', onAbort)
    }

    let bytes: Uint8Array
    try {
      bytes = new Uint8Array(await res.arrayBuffer())
    } catch {
      throw new AuthApiError(res.status, 'bad_reply')
    }
    if (res.ok) {
      if (bytes.length > MAX_REPLY) throw new AuthApiError(res.status, 'bad_reply')
      return bytes
    }
    let code = 'http_error'
    try {
      if (bytes.length <= MAX_REPLY) code = ErrorHttp.decode(bytes).code || code
    } catch {
      // not a protobuf answer: the status is all there is
    }
    const retry = Number(res.headers.get('retry-after'))
    throw new AuthApiError(res.status, code, Number.isFinite(retry) && retry > 0 ? Math.min(retry, 60) * 1000 : 0)
  }

  #tokens(bytes: Uint8Array): Tokens {
    let reply: LoginRefreshResponse
    try {
      reply = LoginRefreshResponse.decode(bytes)
    } catch {
      throw new AuthApiError(200, 'bad_reply')
    }
    if (!reply.accessToken) throw new AuthApiError(200, 'bad_reply')
    return { accessToken: reply.accessToken, expiresIn: reply.expiresIn }
  }

  #account(bytes: Uint8Array): Account {
    let user: UserSummary | undefined
    try {
      user = UserSummary.decode(bytes)
    } catch {
      user = undefined
    }
    if (!user?.id) throw new AuthApiError(200, 'bad_reply')
    return { id: user.id, email: user.email, username: user.username }
  }

  async register(email: string, username: string, password: string, signal?: AbortSignal): Promise<Account> {
    const body = RegisterInput.encode({ email, username, password }).finish()
    const reply = RegisterResponse.decode(await this.#call('POST', '/auth/register/', { body, signal }))
    if (!reply.user?.id) throw new AuthApiError(201, 'bad_reply')
    return { id: reply.user.id, email: reply.user.email, username: reply.user.username }
  }

  /** `sessionOnly`: the refresh cookie goes away when the browser closes. */
  async login(email: string, password: string, sessionOnly: boolean, signal?: AbortSignal): Promise<Tokens> {
    const body = LoginInput.encode({ email, password, sessionOnly }).finish()
    return this.#tokens(await this.#call('POST', '/auth/login/', { body, signal }))
  }

  /** A new access token from the refresh cookie. */
  async refresh(signal?: AbortSignal): Promise<Tokens> {
    return this.#tokens(await this.#call('POST', '/auth/refresh/', { signal }))
  }

  async me(token: string, signal?: AbortSignal): Promise<Account> {
    return this.#account(await this.#call('GET', '/auth/me/', { token, signal }))
  }

  /** Revokes the refresh cookie (and the access token, when given) and clears the cookie. */
  async logout(token?: string, signal?: AbortSignal): Promise<void> {
    await this.#call('POST', '/auth/logout/', { token, signal })
  }
}
