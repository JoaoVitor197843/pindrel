import { describe, expect, it, vi } from 'vitest'
import { ApiError, getProto } from './client'

const text = (b: Uint8Array) => new TextDecoder().decode(b)

describe('getProto', () => {
  it('pede protobuf e decodifica o corpo', async () => {
    vi.mocked(fetch).mockResolvedValue(new Response('oi'))
    expect(await getProto('/x/', text)).toBe('oi')
    expect(vi.mocked(fetch).mock.calls.at(-1)?.[1]?.headers).toEqual({ Accept: 'application/x-protobuf' })
  })

  it('status de erro vira ApiError com o status', async () => {
    vi.mocked(fetch).mockResolvedValue(new Response(null, { status: 503 }))
    await expect(getProto('/x/', text)).rejects.toMatchObject({ status: 503 })
    await expect(getProto('/x/', text)).rejects.toBeInstanceOf(ApiError)
  })

  it('corpo grande demais é recusado antes de decodificar', async () => {
    vi.mocked(fetch).mockResolvedValue(new Response(new Uint8Array(70_000)))
    const decode = vi.fn()
    await expect(getProto('/x/', decode)).rejects.toBeInstanceOf(ApiError)
    expect(decode).not.toHaveBeenCalled()
  })

  it('sem resposta no prazo, aborta; abortar por fora também', async () => {
    vi.mocked(fetch).mockImplementation(
      (_, init) => new Promise((_, reject) => init?.signal?.addEventListener('abort', () => reject(new DOMException('', 'AbortError')))),
    )
    await expect(getProto('/x/', text, { timeoutMs: 20 })).rejects.toThrow()
    const outside = new AbortController()
    const pending = getProto('/x/', text, { signal: outside.signal, timeoutMs: 60_000 })
    outside.abort()
    await expect(pending).rejects.toThrow()
  })
})
