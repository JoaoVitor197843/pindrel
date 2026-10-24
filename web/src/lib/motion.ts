/**
 * Duração de uma transição em ms: zero com "reduzir movimento" ligado (ou sem Web Animations, como no
 * jsdom), para que nada fique esperando uma animação que não vai tocar.
 */
export function ms(duration: number): number {
  if (typeof Element === 'undefined' || typeof Element.prototype.animate !== 'function') return 0
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : duration
}
