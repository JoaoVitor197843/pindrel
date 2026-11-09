import { afterEach, describe, expect, it, vi } from 'vitest'
import { ErrorHttp, LoginInput, LoginRefreshResponse, RegisterInput, RegisterResponse, UserSummary } from '../../types/shared/protos/auth'
import { AuthApi, AuthApiError } from './auth'

const bytes = (b: Uint8Array) => b as unknown as BodyInit
const ok = (b: Uint8Array, status = 200) => new Response(bytes(b), { status })
const fail = (status: number, code: string, headers: Record<string, string> = {}) => new Response(bytes(ErrorHttp.encode({ code, message: 'x' }).finish()), { status, headers })
const tokens = (accessToken = 'a.b.c', expiresIn = 900) => ok(LoginRefreshResponse.encode({ accessToken, expiresIn }).finish())

afterEach(() => vi.useRealTimers())

describe('AuthApi', () => {
  it('login sends the credentials as protobuf and reads the token and its life', async () => {
    const f = vi.fn(async () => tokens('tok.en.x', 900))
    const t = await new AuthApi(f as unknown as typeof fetch).login('a@b.co', 'senha-forte', true)
    expect(t).toEqual({ accessToken: 'tok.en.x', expiresIn: 900 })
    const [path, init] = f.mock.calls[0] as unknown as [string, RequestInit]
    expect(path).toBe('/auth/login/')
    expect(init.method).toBe('POST')
    expect((init.headers as Record<string, string>)['Content-Type']).toBe('application/x-protobuf')
    expect(init.credentials).toBe('same-origin')
    expect(LoginInput.decode(init.body as Uint8Array)).toEqual({ email: 'a@b.co', password: 'senha-forte', sessionOnly: true })
  })

  it('register sends all three fields and returns the account', async () => {
    const f = vi.fn(async () => ok(RegisterResponse.encode({ user: { id: 'u1', email: 'a@b.co', username: 'ana' } }).finish(), 201))
    const u = await new AuthApi(f as unknown as typeof fetch).register('a@b.co', 'ana', 'senha-forte')
    expect(u).toEqual({ id: 'u1', email: 'a@b.co', username: 'ana' })
    expect(RegisterInput.decode((f.mock.calls[0] as unknown as [string, RequestInit])[1].body as Uint8Array)).toEqual({ email: 'a@b.co', username: 'ana', password: 'senha-forte' })
  })

  it('refresh sends no body (the cookie is the credential) and me sends the bearer', async () => {
    const f = vi.fn(async (path: string) => (path === '/auth/me/' ? ok(UserSummary.encode({ id: 'u1', email: 'a@b.co', username: 'ana' }).finish()) : tokens()))
    const api = new AuthApi(f as unknown as typeof fetch)
    await api.refresh()
    const refresh = f.mock.calls[0] as unknown as [string, RequestInit]
    expect(refresh[1].body).toBeUndefined()
    expect((refresh[1].headers as Record<string, string>).Authorization).toBeUndefined()
    await api.me('the.token.x')
    const me = f.mock.calls[1] as unknown as [string, RequestInit]
    expect(me[1].method).toBe('GET')
    expect((me[1].headers as Record<string, string>).Authorization).toBe('Bearer the.token.x')
  })

  it('logout accepts the empty 204', async () => {
    const f = vi.fn(async () => new Response(null, { status: 204 }))
    await expect(new AuthApi(f as unknown as typeof fetch).logout('t.o.k')).resolves.toBeUndefined()
  })

  it('an error carries the status, the code and how long to wait', async () => {
    const f = vi.fn(async () => fail(503, 'server_busy', { 'Retry-After': '5' }))
    const e = await new AuthApi(f as unknown as typeof fetch).login('a@b.co', 'x', false).catch((x) => x)
    expect(e).toBeInstanceOf(AuthApiError)
    expect(e).toMatchObject({ status: 503, code: 'server_busy', retryAfterMs: 5000 })
  })

  it('caps a silly Retry-After, and ignores one that is not a number', async () => {
    const api = (h: string) => new AuthApi((async () => fail(429, 'x', { 'Retry-After': h })) as unknown as typeof fetch)
    expect(await api('99999').login('a@b.co', 'x', false).catch((x) => x.retryAfterMs)).toBe(60_000)
    expect(await api('soon').login('a@b.co', 'x', false).catch((x) => x.retryAfterMs)).toBe(0)
  })

  it('an answer that is not protobuf still tells the status', async () => {
    const f = vi.fn(async () => new Response('<html>bad gateway</html>', { status: 502 }))
    const e = await new AuthApi(f as unknown as typeof fetch).refresh().catch((x) => x)
    expect(e).toMatchObject({ status: 502, code: 'http_error' })
  })

  it('a 200 that is not ours is rejected, not trusted', async () => {
    const garbage = vi.fn(async () => ok(new Uint8Array([0xff, 0xff, 0xff])))
    expect(await new AuthApi(garbage as unknown as typeof fetch).refresh().catch((x) => x.code)).toBe('bad_reply')
    const empty = vi.fn(async () => ok(new Uint8Array()))
    expect(await new AuthApi(empty as unknown as typeof fetch).login('a@b.co', 'x', false).catch((x) => x.code)).toBe('bad_reply')
    expect(await new AuthApi(empty as unknown as typeof fetch).me('t.o.k').catch((x) => x.code)).toBe('bad_reply')
    expect(await new AuthApi(empty as unknown as typeof fetch).register('a@b.co', 'ana', 'senha-forte').catch((x) => x.code)).toBe('bad_reply')
  })

  it('an enormous answer is thrown away undecoded', async () => {
    const big = vi.fn(async () => ok(new Uint8Array(100_000).fill(1)))
    expect(await new AuthApi(big as unknown as typeof fetch).refresh().catch((x) => x.code)).toBe('bad_reply')
  })

  it('no connection is "network", and a server that never answers is "timeout"', async () => {
    const down = vi.fn(async () => {
      throw new TypeError('Failed to fetch')
    })
    expect(await new AuthApi(down as unknown as typeof fetch).refresh().catch((x) => x)).toMatchObject({ status: 0, code: 'network' })

    vi.useFakeTimers()
    const hang = vi.fn((_p: string, init: RequestInit) => new Promise((_, reject) => init.signal!.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')))))
    const pending = new AuthApi(hang as unknown as typeof fetch).refresh().catch((x) => x)
    await vi.advanceTimersByTimeAsync(15_001)
    expect(await pending).toMatchObject({ status: 0, code: 'timeout' })
  })

  it('a caller that gives up is not reported as a failure of the server', async () => {
    const controller = new AbortController()
    const hang = vi.fn((_p: string, init: RequestInit) => new Promise((_, reject) => init.signal!.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')))))
    const pending = new AuthApi(hang as unknown as typeof fetch).refresh(controller.signal).catch((x) => x)
    controller.abort()
    const e = await pending
    expect(e).not.toBeInstanceOf(AuthApiError)
  })
})
