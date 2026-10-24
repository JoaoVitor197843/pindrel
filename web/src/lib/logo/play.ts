import { Scene, buildStage } from './scenes'
import type { LogoTheme } from './season'


// Confetti that outlives the length a scene reports (measured on the prototype's timings).
const TAIL: Partial<Record<LogoTheme, number>> = { normal: 1100, d31: 700, d1: 400 }

export interface Playing {
  /** Total time (ms) until everything is gone and the logo can be tapped again. */
  duration: number
  /** Cuts the scene short and frees everything it created. */
  cancel: () => void
}

function canAnimate(): boolean {
  return typeof Element !== 'undefined' && typeof Element.prototype.animate === 'function'
}

function reducedMotion(): boolean {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/**
 * Plays the scene of `theme` right over `logo` and removes it at the end. With "reduce motion" on (or
 * without the Web Animations API) it only blinks `logo` for 400 ms. Nothing here touches the network.
 */
export function playLogoScene(theme: LogoTheme, logo: HTMLElement): Playing {
  if (!canAnimate() || reducedMotion()) {
    if (canAnimate()) logo.animate([{ opacity: 1 }, { opacity: 0.5 }, { opacity: 1 }], { duration: 400 })
    return { duration: 420, cancel: () => {} }
  }
  const box = logo.getBoundingClientRect()
  const stage = buildStage({ x: box.left + box.width / 2, y: box.top + box.height / 2, scale: box.width / 88 })
  document.body.appendChild(stage.root)
  // the replica takes the real logo's place for the length of the scene
  logo.style.visibility = 'hidden'
  const scene = new Scene(stage)
  const length = scene.run(theme) + (TAIL[theme] ?? 0)
  let done = false
  const timers: ReturnType<typeof setTimeout>[] = []
  const cancel = () => {
    if (done) return
    done = true
    timers.forEach(clearTimeout)
    scene.dispose()
    logo.style.visibility = ''
  }
  timers.push(setTimeout(cancel, length))
  return { duration: length, cancel }
}
