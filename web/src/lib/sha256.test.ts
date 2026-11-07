import { createHash, randomBytes } from 'node:crypto'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { sha256, sha256Js, toHex } from './sha256'

const ref = (b: Uint8Array) => createHash('sha256').update(b).digest('hex')

describe('sha256 em JavaScript puro', () => {
  it('bate com os vetores oficiais', () => {
    const enc = new TextEncoder()
    expect(toHex(sha256Js(enc.encode('')))).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    expect(toHex(sha256Js(enc.encode('abc')))).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
    expect(toHex(sha256Js(enc.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')))).toBe('248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1')
    expect(toHex(sha256Js(new Uint8Array(1_000_000).fill(0x61)))).toBe('cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0')
  })

  it('bate com o Node em todos os tamanhos perto das bordas de bloco e de preenchimento', () => {
    for (let n = 0; n <= 200; n++) {
      const b = new Uint8Array(randomBytes(n))
      expect(toHex(sha256Js(b)), `${n} bytes`).toBe(ref(b))
    }
    for (const n of [511, 512, 513, 1023, 1024, 1025, 65_535, 65_536, 65_537, 524_288]) {
      const b = new Uint8Array(randomBytes(n))
      expect(toHex(sha256Js(b)), `${n} bytes`).toBe(ref(b))
    }
  })

  it('aceita uma fatia que não começa no início do buffer', () => {
    const big = new Uint8Array(randomBytes(5000))
    const part = big.subarray(1234, 4321)
    expect(toHex(sha256Js(part))).toBe(ref(part))
  })

  it('não muda a entrada', () => {
    const b = new Uint8Array(randomBytes(777))
    const copy = b.slice()
    sha256Js(b)
    expect(b).toEqual(copy)
  })

  it('um pedaço de 512 KiB leva uma fração de segundo', () => {
    const b = new Uint8Array(randomBytes(512 * 1024))
    const t0 = performance.now()
    for (let i = 0; i < 4; i++) sha256Js(b)
    expect(performance.now() - t0).toBeLessThan(3000)
  })
})

describe('sha256 do navegador, com o plano B', () => {
  // not unstubAllGlobals: it would also remove the fetch stub of the test setup
  const real = globalThis.crypto
  afterEach(() => vi.stubGlobal('crypto', real))

  it('usa o crypto.subtle quando existe', async () => {
    const b = new Uint8Array(randomBytes(3000))
    expect(toHex(await sha256(b))).toBe(ref(b))
  })

  it('numa página sem crypto.subtle (HTTP comum) calcula do mesmo jeito', async () => {
    vi.stubGlobal('crypto', {})
    const b = new Uint8Array(randomBytes(3000))
    expect(toHex(await sha256(b))).toBe(ref(b))
  })

  it('se o crypto.subtle falhar no meio, o plano B responde', async () => {
    vi.stubGlobal('crypto', { subtle: { digest: () => Promise.reject(new Error('indisponível')) } })
    const b = new Uint8Array(randomBytes(100))
    expect(toHex(await sha256(b))).toBe(ref(b))
  })
})
