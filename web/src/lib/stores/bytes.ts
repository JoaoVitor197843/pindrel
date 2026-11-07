/** A size for people: 1.4 MB, 312 KB, 2.0 GB. Always rounded up a little on the unit it picks, never negative. */
export function formatBytes(n: number): string {
  if (!Number.isFinite(n) || n <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  let v = n
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000
    i++
  }
  return `${i === 0 ? Math.round(v) : v >= 100 ? Math.round(v) : v.toFixed(1)} ${units[i]}`
}
