import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto'

// scrypt with OWASP's minimum (N=2^17, r=8, p=1). The cost and salt live in
// the stored string, so raising the cost later leaves old hashes readable.

const COST = { N: 2 ** 17, r: 8, p: 1 }
const KEY_LENGTH = 32

function derive(password: string, salt: Buffer, N: number, r: number, p: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    // 128·N·r bytes are needed; Node's default ceiling (32 MB) is exactly that, so give room.
    scrypt(password.normalize('NFC'), salt, KEY_LENGTH, { N, r, p, maxmem: 256 * 1024 * 1024 }, (error, key) =>
      error ? reject(error) : resolve(key),
    )
  })
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16)
  const key = await derive(password, salt, COST.N, COST.r, COST.p)
  return `scrypt$${COST.N}$${COST.r}$${COST.p}$${salt.toString('base64url')}$${key.toString('base64url')}`
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, N, r, p, salt, key] = stored.split('$')
  if (scheme !== 'scrypt' || !N || !r || !p || !salt || !key) return false
  const expected = Buffer.from(key, 'base64url')
  const actual = await derive(password, Buffer.from(salt, 'base64url'), Number(N), Number(r), Number(p))
  return actual.length === expected.length && timingSafeEqual(actual, expected)
}
