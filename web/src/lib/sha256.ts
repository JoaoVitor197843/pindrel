// SHA-256 of a piece of a file. The browser's `crypto.subtle` is the fast way, but it exists only on a secure page (HTTPS
// or localhost), and a Pindrel server on a home network is often plain HTTP: there the same hash is computed in plain
// JavaScript, a few hundred MB a second, which is more than a connection sends. Pieces are 512 KiB, so neither way ever
// holds a whole file.

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
])

/** SHA-256 in plain JavaScript. */
export function sha256Js(data: Uint8Array): Uint8Array {
  const h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19])
  const bitLen = data.length * 8
  // the message, a 1 bit, zeros, and the length in bits: a multiple of 64 bytes. Only the tail is copied.
  const full = data.length - (data.length % 64)
  const tailLen = data.length - full
  const padded = new Uint8Array(tailLen + 1 + ((55 - tailLen + 64) % 64) + 8)
  padded.set(data.subarray(full))
  padded[tailLen] = 0x80
  const dv = new DataView(padded.buffer)
  dv.setUint32(padded.length - 8, Math.floor(bitLen / 0x100000000))
  dv.setUint32(padded.length - 4, bitLen >>> 0)
  const w = new Uint32Array(64)
  const block = (src: Uint8Array, at: number) => {
    for (let i = 0; i < 16; i++) {
      const j = at + i * 4
      w[i] = (src[j] << 24) | (src[j + 1] << 16) | (src[j + 2] << 8) | src[j + 3]
    }
    for (let i = 16; i < 64; i++) {
      const a = w[i - 15]
      const b = w[i - 2]
      const s0 = ((a >>> 7) | (a << 25)) ^ ((a >>> 18) | (a << 14)) ^ (a >>> 3)
      const s1 = ((b >>> 17) | (b << 15)) ^ ((b >>> 19) | (b << 13)) ^ (b >>> 10)
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0
    }
    let [a, b, c, d, e, f, g, hh] = h
    for (let i = 0; i < 64; i++) {
      const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))
      const ch = (e & f) ^ (~e & g)
      const t1 = (hh + S1 + ch + K[i] + w[i]) | 0
      const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))
      const maj = (a & b) ^ (a & c) ^ (b & c)
      const t2 = (S0 + maj) | 0
      hh = g
      g = f
      f = e
      e = (d + t1) | 0
      d = c
      c = b
      b = a
      a = (t1 + t2) | 0
    }
    h[0] += a
    h[1] += b
    h[2] += c
    h[3] += d
    h[4] += e
    h[5] += f
    h[6] += g
    h[7] += hh
  }
  for (let at = 0; at < full; at += 64) block(data, at)
  for (let at = 0; at < padded.length; at += 64) block(padded, at)
  const out = new Uint8Array(32)
  const odv = new DataView(out.buffer)
  for (let i = 0; i < 8; i++) odv.setUint32(i * 4, h[i])
  return out
}

/** SHA-256 of `data`, with the browser's implementation when the page may use it. */
export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const subtle = globalThis.crypto?.subtle
  if (subtle) {
    try {
      return new Uint8Array(await subtle.digest('SHA-256', data as BufferSource))
    } catch {
      // fall through to the plain JavaScript one
    }
  }
  return sha256Js(data)
}

export const toHex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
