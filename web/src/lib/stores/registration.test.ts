import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../types/shared/protos/server'
import { selection } from './servers.svelte'

const info = (name: string, registrationEnabled: boolean) => new Response(ServerInfo.encode({ name, registrationEnabled }).finish() as unknown as BodyInit, { status: 200 })

beforeEach(() => {
  selection.registrationEnabled = null
})

describe('registrationEnabled (from /server/info/)', () => {
  it('follows what the server says, open or closed', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(info('Casa', true))
    await selection.check()
    expect(selection.registrationEnabled).toBe(true)
    vi.mocked(fetch).mockResolvedValueOnce(info('Casa', false))
    await selection.check()
    expect(selection.registrationEnabled).toBe(false)
  })

  it('stays unknown when the answer is not a ServerInfo (a bare 200, a 404, a page, noise)', async () => {
    for (const res of [new Response(null, { status: 200 }), new Response(null, { status: 404 }), new Response('<html></html>', { status: 200 }), new Response(new Uint8Array([0xff, 0xfe, 0xfd]) as unknown as BodyInit, { status: 200 }), info('', false)]) {
      vi.mocked(fetch).mockResolvedValueOnce(res)
      await selection.check()
      expect(selection.registrationEnabled).toBeNull()
    }
  })

  it('keeps the last thing the server said when it stops answering', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(info('Casa', false))
    await selection.check()
    vi.mocked(fetch).mockRejectedValueOnce(new TypeError('Failed to fetch'))
    await selection.check()
    expect(selection.registrationEnabled).toBe(false)
    vi.mocked(fetch).mockResolvedValueOnce(new Response(null, { status: 200 }))
    await selection.check()
    expect(selection.registrationEnabled).toBe(false)
  })

  it('an oversized answer is not decoded', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response(new Uint8Array(10_000).fill(10) as unknown as BodyInit, { status: 200 }))
    await selection.check()
    expect(selection.registrationEnabled).toBeNull()
  })
})
