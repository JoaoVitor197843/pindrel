/** Curva cúbica de Bézier como no CSS/Flutter: `Cubic(x1, y1, x2, y2)`, de 0..1 em 0..1. */
export function cubicBezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
  const ax = 3 * x1 - 3 * x2 + 1
  const bx = 3 * x2 - 6 * x1
  const cx = 3 * x1
  const ay = 3 * y1 - 3 * y2 + 1
  const by = 3 * y2 - 6 * y1
  const cy = 3 * y1
  const sample = (a: number, b: number, c: number, s: number) => ((a * s + b) * s + c) * s
  return (x) => {
    if (x <= 0) return 0
    if (x >= 1) return 1
    let lo = 0
    let hi = 1
    let s = x
    for (let i = 0; i < 24; i++) {
      s = (lo + hi) / 2
      if (sample(ax, bx, cx, s) < x) lo = s
      else hi = s
    }
    return sample(ay, by, cy, s)
  }
}

/** `Curves.easeIn` e `Curves.easeOut` do Flutter. */
export const easeIn = cubicBezier(0.42, 0, 1, 1)
export const easeOut = cubicBezier(0, 0, 0.58, 1)
