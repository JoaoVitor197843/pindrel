/**
 * Duration of a transition in ms: zero with "reduce motion" on (or without Web Animations, as in
 * jsdom), so nothing waits for an animation that will not play.
 */
export function ms(duration: number): number {
  if (typeof Element === 'undefined' || typeof Element.prototype.animate !== 'function') return 0
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : duration
}
