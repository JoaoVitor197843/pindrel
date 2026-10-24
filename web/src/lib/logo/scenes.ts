import {
  BAL,
  BFLY,
  BIGHEART,
  BONFIRE,
  BUNNY,
  CARROT,
  CUPID,
  GP,
  HAT_NATAL,
  HAT_PARTY,
  HEART_ICON,
  MASK,
  NOTE,
  O,
  PBAL,
  PUMP,
  SLEIGH,
  SNOWFLAKE,
  SPARK_SVG,
  TAG,
  TREE,
  VAMP,
  WITCH,
  gift,
} from './art'
import type { LogoTheme } from './season'

/** Time the five taps' streaks take to converge on the logo (the first beat of the "normal" scene). */
const HIT = 1000
const SERIF = 'serif'
const MONO = 'monospace'

/** The stage the scene plays on: a card with a replica of the logo at its center. */
export interface StageEls {
  root: HTMLElement
  stage: HTMLElement
  logo: HTMLElement
  flash: HTMLElement
  pl: HTMLElement
  swap: HTMLElement
  oring: HTMLElement
}

/** Builds the (detached) stage. The replica copies the real logo's colors, so the scene never touches the real one. */
export function buildStage(anchor: { x: number; y: number; scale: number }): StageEls {
  const el = (css: string, parent?: HTMLElement): HTMLElement => {
    const d = document.createElement('div')
    d.style.cssText = css
    parent?.appendChild(d)
    return d
  }
  // No card: the stage is the prototype's 388x280 box, shrunk so its 88 px logo lands exactly on the real
  // one (`anchor.scale` = real size / 88) and centered on it; what flies out is drawn straight over the page.
  const root = el('position:fixed;left:0;top:0;width:0;height:0;z-index:60;pointer-events:none;')
  const stage = el(
    `position:absolute;left:${anchor.x}px;top:${anchor.y}px;width:388px;height:280px;transform:translate(-50%,-50%) scale(${anchor.scale});display:flex;align-items:center;justify-content:center;`,
    root,
  )
  const logo = el(
    `position:relative;z-index:2;width:88px;height:88px;border-radius:20px;background:#4a5d44;color:#eae6df;display:flex;align-items:center;justify-content:center;font-family:${SERIF};font-size:54px;line-height:1;overflow:hidden;`,
    stage,
  )
  const flash = el('position:absolute;inset:0;background:#8fb58f;opacity:0;', logo)
  const pl = el('position:relative;z-index:1;', logo)
  pl.textContent = 'P'
  const swap = el(
    'position:absolute;inset:0;z-index:2;opacity:0;display:flex;align-items:center;justify-content:center;overflow:hidden;',
    logo,
  )
  const oring = el(
    'position:absolute;inset:0;z-index:3;border:4px solid #e2862c;border-radius:20px;box-sizing:border-box;opacity:0;',
    logo,
  )
  return { root, stage, logo, flash, pl, swap, oring }
}

const rnd = (a: number, b: number) => a + Math.random() * (b - a)
const pick = <T>(a: readonly T[]): T => a[Math.floor(Math.random() * a.length)]!
type Frames = Keyframe[]
type Opts = KeyframeAnimationOptions

function twinkle(ph: number): Frames {
  const fr: Frames = [
    { opacity: 0, offset: 0 },
    { opacity: 1, offset: 0.1 },
  ]
  let o = 0.14
  for (let j = 0; j < 8; j++) {
    fr.push({ opacity: (j + ph) % 2 ? 1 : 0.35, offset: o })
    o += 0.09
  }
  fr.push({ opacity: 1, offset: 0.88 }, { opacity: 0, offset: 1 })
  return fr
}

/** Plays one scene on a stage; every timer and element it creates dies with `dispose()`. */
export class Scene {
  private timers = new Set<number>()
  private readonly els: StageEls

  constructor(els: StageEls) {
    this.els = els
  }

  /** Runs the theme's scene and returns how long (ms) it takes. */
  run(theme: LogoTheme): number {
    return this[theme]()
  }

  dispose() {
    this.timers.forEach((t) => clearTimeout(t))
    this.timers.clear()
    this.els.root.remove()
  }

  // ---- helpers ----------------------------------------------------------------------------------------------

  private later(fn: () => void, ms: number) {
    const id = window.setTimeout(() => {
      this.timers.delete(id)
      fn()
    }, ms)
    this.timers.add(id)
  }

  // An absolute element at the stage center (or placed by css), invisible until animated.
  private mk(css: string, html?: string): HTMLElement {
    const d = document.createElement('div')
    d.style.cssText = `position:absolute;z-index:1;pointer-events:none;opacity:0;${css}`
    if (html) d.innerHTML = html
    this.els.stage.appendChild(d)
    return d
  }

  // Animates and removes the element at the end.
  private fly(el: HTMLElement, frames: Frames, opts: Opts) {
    const a = el.animate(frames, { ...opts, fill: 'both' })
    a.onfinish = () => el.remove()
    return a
  }

  private ring(color: string, at: number) {
    this.later(() => {
      for (const dl of [0, 140]) {
        const r = this.mk(`width:88px;height:88px;border-radius:20px;border:2px solid ${color};`)
        this.fly(r, [{ transform: 'scale(1)', opacity: 0.7 }, { transform: 'scale(2.5)', opacity: 0 }], {
          duration: 800,
          delay: dl,
          easing: 'cubic-bezier(.2,.6,.3,1)',
        })
      }
    }, at)
  }

  private bump(color: string) {
    const { logo, flash } = this.els
    flash.style.background = color
    logo.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.1)' }, { transform: 'scale(1)' }], {
      duration: 240,
      easing: 'ease-out',
    })
    flash.animate([{ opacity: 0 }, { opacity: 0.5 }, { opacity: 0 }], { duration: 240 })
  }

  private pop(color: string) {
    const { logo, flash } = this.els
    flash.style.background = color
    logo.animate(
      [
        { transform: 'scale(1)', offset: 0 },
        { transform: 'scale(0.92)', offset: 0.45 },
        { transform: 'scale(0.92)', offset: 0.5 },
        { transform: 'scale(1.2)', offset: 0.62 },
        { transform: 'scale(1)', offset: 0.8 },
        { transform: 'scale(1)', offset: 1 },
      ],
      { duration: HIT + 500, easing: 'ease-out' },
    )
    flash.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 0, offset: 0.66 },
        { opacity: 0.7, offset: 0.74 },
        { opacity: 0, offset: 1 },
      ],
      { duration: HIT + 500 },
    )
  }

  private setSwap(html: string, bg: string) {
    const { swap } = this.els
    swap.getAnimations().forEach((a) => a.cancel())
    swap.style.background = bg
    swap.innerHTML = html
  }

  private q<T extends Element = SVGElement>(sel: string): T {
    return this.els.swap.querySelector<T>(sel)!
  }

  // Shows a figure in place of the P (the swap layer) and returns its wrapper.
  private scene(html: string, bg: string, D: number, fadeAt = 0.86): HTMLElement {
    this.setSwap(`<div style="position:absolute;inset:0;">${html}</div>`, bg)
    this.els.swap.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 1, offset: 0.06 },
        { opacity: 1, offset: fadeAt },
        { opacity: 0, offset: 1 },
      ],
      { duration: D, fill: 'both' },
    )
    return this.els.swap.firstChild as HTMLElement
  }

  // Grows from left to right (written lines).
  private sx(el: SVGElement, dl: number, du: number) {
    el.style.transformBox = 'fill-box'
    el.style.transformOrigin = '0% 50%'
    el.animate([{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], {
      duration: du,
      delay: dl,
      fill: 'both',
      easing: 'ease-out',
    })
  }

  private burst(n: number, dl: number, cols: string[], r0: number, r1: number) {
    for (let i = 0; i < n; i++) {
      const a = (Math.PI * 2 * i) / n + rnd(-0.2, 0.2)
      const d = rnd(r0, r1)
      const dx = Math.cos(a) * d
      const dy = Math.sin(a) * d
      const s = this.mk('width:14px;height:14px;', SPARK_SVG(pick(cols)))
      this.fly(
        s,
        [
          { transform: 'translate(0,0) scale(0.3) rotate(0deg)', opacity: 0, offset: 0 },
          { transform: `translate(${dx}px,${dy}px) scale(1.3) rotate(120deg)`, opacity: 1, offset: 0.4 },
          { transform: `translate(${dx * 1.2}px,${dy * 1.2 + 12}px) scale(0) rotate(240deg)`, opacity: 0, offset: 1 },
        ],
        { duration: 900, delay: dl, easing: 'ease-out' },
      )
    }
  }

  // Alternating rotation (samba sway, ears).
  private wob(el: SVGElement, amps: number[], dl: number, step: number, origin?: string) {
    const fr: Frames = [{ transform: 'rotate(0deg)', offset: 0 }]
    amps.forEach((a, i) => fr.push({ transform: `rotate(${a}deg)`, offset: (i + 1) / (amps.length + 1) }))
    fr.push({ transform: 'rotate(0deg)', offset: 1 })
    if (origin) el.style.transformOrigin = origin
    return el.animate(fr, { duration: step * (amps.length + 1), delay: dl, easing: 'ease-in-out' })
  }

  // Arc throw with a fall (eggs, pumpkins, gifts).
  private toss(el: HTMLElement, dx: number, peak: number, end: number, rot: number, delay: number, sc: number) {
    const at = `translate(${dx}px,${end}px) rotate(${rot}deg) scale(1)`
    this.fly(
      el,
      [
        {
          transform: `translate(0,0) rotate(0deg) scale(${sc})`,
          opacity: 0,
          offset: 0,
          easing: 'cubic-bezier(.2,.8,.4,1)',
        },
        {
          transform: `translate(${dx * 0.55}px,${-peak}px) rotate(${rot * 0.5}deg) scale(1)`,
          opacity: 1,
          offset: 0.38,
          easing: 'cubic-bezier(.5,0,.9,.6)',
        },
        { transform: at, opacity: 1, offset: 0.9 },
        { transform: at, opacity: 0, offset: 1 },
      ],
      { duration: 1300, delay },
    )
  }

  private streaks(cols: string[]) {
    for (let i = 0; i < 22; i++) {
      const ang = (360 * i) / 22 + rnd(-6, 6)
      const len = Math.round(rnd(36, 80))
      const dl = Math.round(rnd(0, 420))
      const s = this.mk(`width:${len}px;height:3px;border-radius:2px;background:${cols[i % cols.length]};`)
      this.fly(
        s,
        [
          { transform: `rotate(${ang}deg) translateX(290px) scaleX(1)`, opacity: 0 },
          { transform: `rotate(${ang}deg) translateX(190px) scaleX(1)`, opacity: 0.9, offset: 0.25 },
          { transform: `rotate(${ang}deg) translateX(62px) scaleX(0.25)`, opacity: 0 },
        ],
        { duration: HIT - dl, delay: dl, easing: 'cubic-bezier(.5,0,.9,.6)' },
      )
    }
  }

  private snowfall(n: number, d0: number, d1: number) {
    for (let i = 0; i < n; i++) {
      const x = rnd(-180, 180)
      const sw = rnd(-26, 26)
      const sz = Math.round(rnd(11, 18))
      const f = this.mk(`font-size:${sz}px;line-height:1;color:${i % 3 === 0 ? '#cfe3ff' : '#f2efe8'};`, SNOWFLAKE)
      this.fly(
        f,
        [
          { transform: `translate(${x}px,-150px) rotate(0deg)`, opacity: 0, offset: 0 },
          { transform: `translate(${x + sw * 0.3}px,-100px) rotate(40deg)`, opacity: 0.9, offset: 0.1 },
          { transform: `translate(${x + sw}px,140px) rotate(260deg)`, opacity: 0.9, offset: 0.88 },
          { transform: `translate(${x + sw}px,155px) rotate(280deg)`, opacity: 0, offset: 1 },
        ],
        { duration: Math.round(rnd(1700, 2400)), delay: Math.round(rnd(d0, d1)), easing: 'linear' },
      )
    }
  }

  private conf(n: number, d0: number, d1: number, cs?: string[]) {
    const cc = cs ?? ['#e9558f', '#2f80ed', '#4d6b4d', '#f4f1ea', '#e2862c', '#f2c94c']
    for (let k = 0; k < n; k++) {
      const w = Math.round(rnd(5, 8))
      const h = Math.round(rnd(8, 12))
      const an = rnd(-Math.PI * 0.95, -Math.PI * 0.05)
      const ds = rnd(90, 170)
      const dx = Math.cos(an) * ds
      const dy = Math.sin(an) * ds
      const fall = rnd(140, 200)
      const rot = rnd(-540, 540)
      const el = this.mk(`width:${w}px;height:${h}px;background:${pick(cc)};border-radius:1px;`)
      const end = `translate(${dx * 1.15}px,${dy + fall}px) rotate(${rot}deg)`
      this.fly(
        el,
        [
          { transform: 'translate(0,0) rotate(0deg)', opacity: 0, offset: 0, easing: 'cubic-bezier(.1,.7,.3,1)' },
          {
            transform: `translate(${dx}px,${dy}px) rotate(${rot * 0.4}deg)`,
            opacity: 1,
            offset: 0.35,
            easing: 'cubic-bezier(.4,0,.8,.6)',
          },
          { transform: end, opacity: 1, offset: 0.9 },
          { transform: end, opacity: 0, offset: 1 },
        ],
        { duration: 1500, delay: Math.round(rnd(d0, d1)) },
      )
    }
  }

  private rain(n: number, d0: number, d1: number) {
    const cc = ['#e9558f', '#2f80ed', '#4d6b4d', '#f4f1ea', '#e2862c', '#f2c94c']
    for (let k = 0; k < n; k++) {
      const x = rnd(-185, 185)
      const sw = rnd(-30, 30)
      const rot = rnd(-540, 540)
      const el = this.mk(
        `width:${Math.round(rnd(5, 8))}px;height:${Math.round(rnd(8, 12))}px;background:${pick(cc)};border-radius:1px;`,
      )
      this.fly(
        el,
        [
          { transform: `translate(${x}px,-150px) rotate(0deg)`, opacity: 0, offset: 0 },
          { transform: `translate(${x}px,-130px) rotate(${rot * 0.1}deg)`, opacity: 1, offset: 0.1 },
          { transform: `translate(${x + sw}px,140px) rotate(${rot}deg)`, opacity: 0.9, offset: 0.9 },
          { transform: `translate(${x + sw}px,155px) rotate(${rot}deg)`, opacity: 0, offset: 1 },
        ],
        { duration: Math.round(rnd(1400, 1900)), delay: Math.round(rnd(d0, d1)), easing: 'linear' },
      )
    }
  }

  // Fireworks: list of [cx, cy, delay]; n particles per burst, radius between dmin and dmax, bc = flash on the logo.
  private fw(list: [number, number, number][], cols: string[], n: number, dmin: number, dmax: number, bc: string) {
    for (const [cx, cy, d] of list) {
      const r = this.mk('width:5px;height:5px;border-radius:50%;background:#f2c94c;')
      this.fly(
        r,
        [
          { transform: 'translate(0,0)', opacity: 0, offset: 0 },
          { transform: 'translate(0,0)', opacity: 1, offset: 0.03 },
          { transform: `translate(${cx}px,${cy}px)`, opacity: 1, offset: 0.95 },
          { transform: `translate(${cx}px,${cy}px)`, opacity: 0, offset: 1 },
        ],
        { duration: 340, delay: d, easing: 'cubic-bezier(.3,.6,.4,1)' },
      )
      for (let i = 0; i < n; i++) {
        const a = (Math.PI * 2 * i) / n
        const dist = rnd(dmin, dmax)
        const dx = Math.cos(a) * dist
        const dy = Math.sin(a) * dist
        const s = this.mk(`width:4px;height:4px;border-radius:50%;background:${pick(cols)};`)
        this.fly(
          s,
          [
            { transform: `translate(${cx}px,${cy}px) scale(1)`, opacity: 0, offset: 0 },
            { transform: `translate(${cx}px,${cy}px) scale(1)`, opacity: 1, offset: 0.05 },
            {
              transform: `translate(${cx + dx}px,${cy + dy}px) scale(1)`,
              opacity: 1,
              offset: 0.55,
              easing: 'ease-in',
            },
            { transform: `translate(${cx + dx * 1.1}px,${cy + dy + 28}px) scale(0.5)`, opacity: 0, offset: 1 },
          ],
          { duration: 1000, delay: d + 330, easing: 'cubic-bezier(.1,.7,.3,1)' },
        )
      }
      this.later(() => this.bump(bc), d + 330)
    }
  }

  // Trail of sparks behind a moving element (reads its real position every 70 ms).
  private trail(el: HTMLElement, dur: number) {
    const t0 = Date.now()
    const tick = () => {
      if (Date.now() - t0 > dur || !el.isConnected) return
      const r = el.getBoundingClientRect()
      const s = this.els.stage.getBoundingClientRect()
      const k = s.width / this.els.stage.offsetWidth || 1 // the stage is scaled
      const x = (r.left + r.width / 2 - s.left) / k - 50
      const y = (r.top + r.height / 2 - s.top) / k + 6
      const st = this.mk(
        `left:${x}px;top:${y}px;width:6px;height:6px;border-radius:50%;background:${pick(['#f2c94c', '#f4f1ea', '#9fd0f0'])};`,
      )
      this.fly(st, [{ transform: 'scale(1)', opacity: 0.9 }, { transform: 'translate(-16px,6px) scale(0.2)', opacity: 0 }], {
        duration: 700,
      })
      this.later(tick, 70)
    }
    tick()
  }

  // ---- scenes: each one fires it and returns its duration (ms) ------------------------------------------------

  private normal(): number {
    this.streaks(['#4d6b4d', '#6f9a6f', '#9cc29c', '#f2efe8', '#6f9a6f', '#9cc29c'])
    this.pop('#8fb58f')
    this.ring('#6f9a6f', HIT - 60)
    this.later(() => {
      const D = 1500
      const el = this.scene(NOTE, '#4d6b4d', D, 0.9)
      el.animate(
        [
          { transform: 'scale(0.6) rotate(-8deg)', offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
          { transform: 'scale(1.06) rotate(2deg)', offset: 0.12 },
          { transform: 'scale(1) rotate(0deg)', offset: 0.2 },
          { transform: 'scale(1) rotate(0deg)', offset: 1 },
        ],
        { duration: D, fill: 'both' },
      )
      this.sx(this.q('#t0'), 100, 240)
      this.sx(this.q('#t1'), 380, 240)
      this.sx(this.q('#t2'), 660, 200)
      this.sx(this.q('#t3'), 900, 160)
      const P = (x: number, y: number, o: number, op: number): Keyframe => ({
        transform: `translate(${x}px,${y}px)`,
        opacity: op,
        offset: o,
      })
      this.q('#pen').animate(
        [
          P(26, 22, 0, 0),
          P(26, 22, 0.05, 1),
          P(26, 22.5, 0.0667, 1),
          P(56, 22.5, 0.2267, 1),
          P(26, 36, 0.2533, 1),
          P(64, 36, 0.4133, 1),
          P(26, 46, 0.44, 1),
          P(58, 46, 0.5733, 1),
          P(26, 56, 0.6, 1),
          P(50, 56, 0.7067, 1),
          P(66, 62, 0.8, 0),
          P(66, 62, 1, 0),
        ],
        { duration: D, fill: 'both' },
      )
      const chk = this.q('#chk')
      chk.style.transformBox = 'fill-box'
      chk.style.transformOrigin = '50% 50%'
      chk.animate(
        [
          { transform: 'scale(0)', opacity: 0, offset: 0 },
          { transform: 'scale(0)', opacity: 0, offset: 0.66 },
          { transform: 'scale(1.4)', opacity: 1, offset: 0.8 },
          { transform: 'scale(1)', opacity: 1, offset: 0.9 },
          { transform: 'scale(1)', opacity: 1, offset: 1 },
        ],
        { duration: D, fill: 'both' },
      )
      this.later(() => this.bump('#8fb58f'), 1050)
      this.burst(8, 1050, ['#f2c94c', '#f4f1ea', '#9cc29c', '#8fb58f'], 55, 95)
      this.conf(16, 1050, 1250, ['#4d6b4d', '#6f9a6f', '#9cc29c', '#f2efe8', '#f2c94c'])
      this.ring('#9cc29c', 1050)
    }, HIT - 100)
    return HIT + 1600
  }

  private halloween(): number {
    const { swap, oring, logo } = this.els
    const D = 1800
    swap.getAnimations().forEach((a) => a.cancel())
    swap.style.background = '#2b1a3a'
    swap.innerHTML = `<div style="position:absolute;inset:0;">${VAMP}</div>`
    const face = swap.firstChild as HTMLElement
    const mouth = this.q('#mouth')
    const fade: Frames = [
      { opacity: 0, offset: 0 },
      { opacity: 1, offset: 0.06 },
      { opacity: 1, offset: 0.84 },
      { opacity: 0, offset: 1 },
    ]
    swap.animate(fade, { duration: D, fill: 'both' })
    oring.animate(fade, { duration: D, fill: 'both' })
    const fr: Frames = [
      { transform: 'translateY(100%) rotate(0deg)', offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
      { transform: 'translateY(0) rotate(0deg)', offset: 0.24 },
    ]
    let o = 0.28
    for (let k = 0; k < 10; k++) {
      fr.push({ transform: `translateY(${k % 2 ? 2 : -3}px) rotate(${k % 2 ? 3 : -3}deg)`, offset: o })
      o += 0.04
    }
    fr.push(
      { transform: 'translateY(0) rotate(0deg)', offset: 0.72 },
      { transform: 'translateY(100%) rotate(0deg)', offset: 0.88, easing: 'ease-in' },
      { transform: 'translateY(100%) rotate(0deg)', offset: 1 },
    )
    face.animate(fr, { duration: D, fill: 'both' })
    mouth.style.transformBox = 'fill-box'
    mouth.style.transformOrigin = '50% 0%'
    mouth.animate([{ transform: 'scaleY(1)' }, { transform: 'scaleY(0.5)' }], {
      duration: 100,
      delay: Math.round(D * 0.28),
      iterations: 8,
      direction: 'alternate',
    })
    logo.animate(
      [
        { transform: 'scale(1)', offset: 0 },
        { transform: 'scale(1.08)', offset: 0.1 },
        { transform: 'scale(1.08)', offset: 0.7 },
        { transform: 'scale(1)', offset: 0.9 },
        { transform: 'scale(1)', offset: 1 },
      ],
      { duration: D, easing: 'ease-out' },
    )
    for (let i = 0; i < 9; i++) {
      const s = Math.round(rnd(26, 38))
      const p = this.mk(`width:${s}px;height:${Math.round(s * 0.94)}px;`, PUMP)
      this.toss(p, rnd(-130, 130), rnd(60, 105), rnd(125, 150), rnd(-240, 240), Math.round(rnd(550, 750)), 0.4)
    }
    for (let j = 0; j < 3; j++) {
      const dir = j === 1 ? -1 : 1
      const yEnd = -rnd(80, 120)
      const w = this.mk('width:52px;height:42px;', WITCH)
      const last = `translate(${dir * 310}px,${yEnd}px) rotate(${-8 * dir}deg) scale(${dir},1)`
      this.fly(
        w,
        [
          { transform: `translate(0,0) rotate(${-6 * dir}deg) scale(${0.3 * dir},0.3)`, opacity: 0, offset: 0 },
          { transform: `translate(${dir * 55}px,-30px) rotate(${-10 * dir}deg) scale(${dir},1)`, opacity: 1, offset: 0.22 },
          {
            transform: `translate(${dir * 150}px,${yEnd * 0.35}px) rotate(${6 * dir}deg) scale(${dir},1)`,
            opacity: 1,
            offset: 0.6,
          },
          {
            transform: `translate(${dir * 280}px,${yEnd}px) rotate(${-8 * dir}deg) scale(${dir},1)`,
            opacity: 1,
            offset: 0.92,
          },
          { transform: last, opacity: 0, offset: 1 },
        ],
        { duration: 1300, delay: 650 + j * 280, easing: 'ease-in-out' },
      )
    }
    this.ring(O, 500)
    this.ring('#8a6ad8', 900)
    return 2500
  }

  private d24(): number {
    const { swap, logo } = this.els
    const D = 3000
    this.setSwap(
      `<div id="num" style="position:relative;font-family:${SERIF};font-size:44px;line-height:1;color:#f4f1ea;">24</div><div id="hat" style="position:absolute;inset:0;opacity:0;">${HAT_NATAL}</div>`,
      '#2d4a37',
    )
    const num = this.q<HTMLElement>('#num')
    const hat = this.q<HTMLElement>('#hat')
    swap.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 1, offset: 0.06 },
        { opacity: 1, offset: 0.86 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D, fill: 'both' },
    )
    num.animate(
      [
        { transform: 'scale(0.7)', opacity: 0, offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: 'scale(1.1)', opacity: 1, offset: 0.5 },
        { transform: 'scale(1)', opacity: 1, offset: 1 },
      ],
      { duration: 500, fill: 'both' },
    )
    hat.animate(
      [
        { transform: 'translateY(-50px)', opacity: 0, offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: 'translateY(4px)', opacity: 1, offset: 0.6 },
        { transform: 'translateY(0)', opacity: 1, offset: 1 },
      ],
      { duration: 450, delay: 600, fill: 'both' },
    )
    logo.animate(
      [
        { transform: 'scale(1)', offset: 0 },
        { transform: 'scale(1.1)', offset: 0.08 },
        { transform: 'scale(1)', offset: 0.18 },
        { transform: 'scale(1)', offset: 1 },
      ],
      { duration: D, easing: 'ease-out' },
    )
    const floor = this.mk(
      'left:0;right:0;bottom:0;height:16px;background:#e8ecf5;border-radius:10px 10px 0 0;transform-origin:50% 100%;',
    )
    this.fly(
      floor,
      [
        { transform: 'scaleY(0)', opacity: 1, offset: 0 },
        { transform: 'scaleY(1)', opacity: 1, offset: 0.12 },
        { transform: 'scaleY(1)', opacity: 1, offset: 0.9 },
        { transform: 'scaleY(1)', opacity: 0, offset: 1 },
      ],
      { duration: 2900, delay: 100 },
    )
    const tree = this.mk('width:70px;height:112px;transform-origin:50% 100%;', TREE)
    const at = 'translate(112px,70px)'
    this.fly(
      tree,
      [
        { transform: `${at} scale(1,0)`, opacity: 1, offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: `${at} scale(1.04,1.1)`, opacity: 1, offset: 0.25 },
        { transform: `${at} scale(1,1)`, opacity: 1, offset: 0.35 },
        { transform: `${at} scale(1,1)`, opacity: 1, offset: 0.9 },
        { transform: `${at} scale(1,1)`, opacity: 0, offset: 1 },
      ],
      { duration: 2650, delay: 350 },
    )
    tree.querySelectorAll('.orn').forEach((orn, i) => {
      orn.animate([{ opacity: 1 }, { opacity: 0.3 }], {
        duration: 420 + i * 70,
        delay: 900,
        iterations: 5,
        direction: 'alternate',
      })
    })
    const gifts: [number, number][] = [
      [82, 26],
      [146, 24],
      [-10, 24],
      [-52, 22],
      [112, 22],
    ]
    gifts.forEach(([x, s], i) => {
      const y = 126 - s / 2
      const dl = 900 + i * 140
      const p = pick(GP)
      const el = this.mk(`width:${s}px;height:${s}px;`, gift(p[0], p[1]))
      this.fly(
        el,
        [
          { transform: `translate(${x}px,${y - 44}px) scale(0.4)`, opacity: 0, offset: 0, easing: 'cubic-bezier(.3,.9,.4,1)' },
          { transform: `translate(${x}px,${y}px) scale(1.1,0.9)`, opacity: 1, offset: 0.3 },
          { transform: `translate(${x}px,${y}px) scale(1,1)`, opacity: 1, offset: 0.45 },
          { transform: `translate(${x}px,${y}px) scale(1,1)`, opacity: 1, offset: 0.9 },
          { transform: `translate(${x}px,${y}px) scale(1,1)`, opacity: 0, offset: 1 },
        ],
        { duration: 2900 - dl },
      )
    })
    const cols = ['#d9453f', '#f2c94c', '#3dbb6a', '#2f80ed']
    const n = 9
    const str = this.mk('left:0;right:0;top:12px;height:2px;background:#4a4f48;')
    this.fly(
      str,
      [
        { opacity: 0, offset: 0 },
        { opacity: 1, offset: 0.1 },
        { opacity: 1, offset: 0.88 },
        { opacity: 0, offset: 1 },
      ],
      { duration: 2800, delay: 200 },
    )
    for (let i = 0; i < n; i++) {
      const b = this.mk(
        `left:${((i + 0.5) / n) * 100}%;margin-left:-4px;top:${10 + Math.round(8 * Math.sin((i / (n - 1)) * Math.PI))}px;width:8px;height:8px;border-radius:50%;background:${cols[i % 4]};`,
      )
      this.fly(b, twinkle(i % 2), { duration: 2800, delay: 250 + i * 40, easing: 'linear' })
    }
    this.snowfall(12, 300, 1500)
    this.ring('#3a7d52', 700)
    this.ring('#d9453f', 1000)
    return D + 100
  }

  private d25(): number {
    const { swap, logo, flash } = this.els
    const D = 3200
    this.setSwap(
      `<div id="num" style="position:relative;font-family:${SERIF};font-size:44px;line-height:1;color:#f4f1ea;">25</div><div id="shine" style="position:absolute;top:-26px;left:0;width:16px;height:140px;background:#ffffff;opacity:0;transform:translateX(-30px) rotate(20deg);"></div>`,
      '#b8352f',
    )
    const num = this.q<HTMLElement>('#num')
    const shine = this.q<HTMLElement>('#shine')
    swap.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 1, offset: 0.05 },
        { opacity: 1, offset: 0.86 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D, fill: 'both' },
    )
    num.animate(
      [
        { transform: 'scale(0) rotate(-12deg)', offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: 'scale(1.35) rotate(5deg)', offset: 0.5 },
        { transform: 'scale(0.94) rotate(-2deg)', offset: 0.75 },
        { transform: 'scale(1) rotate(0deg)', offset: 1 },
      ],
      { duration: 520, fill: 'both' },
    )
    shine.animate(
      [
        { transform: 'translateX(-30px) rotate(20deg)', opacity: 0.5 },
        { transform: 'translateX(120px) rotate(20deg)', opacity: 0.5 },
      ],
      { duration: 500, delay: 700, fill: 'both' },
    )
    logo.animate(
      [
        { transform: 'scale(1)', offset: 0 },
        { transform: 'scale(1.14)', offset: 0.06 },
        { transform: 'scale(0.96)', offset: 0.12 },
        { transform: 'scale(1.06)', offset: 0.2 },
        { transform: 'scale(1)', offset: 0.3 },
        { transform: 'scale(1)', offset: 1 },
      ],
      { duration: D },
    )
    flash.style.background = '#f2c94c'
    flash.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 0.5, offset: 0.06 },
        { opacity: 0, offset: 0.2 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D },
    )
    for (let i = 0; i < 9; i++) {
      const s = Math.round(rnd(24, 34))
      const p = pick(GP)
      const g = this.mk(`width:${s}px;height:${s}px;`, gift(p[0], p[1]))
      this.toss(g, rnd(-140, 140), rnd(60, 110), rnd(120, 150), rnd(-240, 240), Math.round(rnd(350, 600)), 0.4)
    }
    const sl = this.mk('width:156px;height:58px;', SLEIGH)
    this.fly(
      sl,
      [
        { transform: 'translate(0,0) scale(0.25) rotate(0deg)', opacity: 0, offset: 0 },
        { transform: 'translate(45px,-18px) scale(0.7) rotate(-6deg)', opacity: 1, offset: 0.2 },
        { transform: 'translate(140px,-60px) scale(1) rotate(-10deg)', opacity: 1, offset: 0.5 },
        { transform: 'translate(250px,-105px) scale(1) rotate(-12deg)', opacity: 1, offset: 0.8 },
        { transform: 'translate(350px,-140px) scale(1.05) rotate(-12deg)', opacity: 0, offset: 1 },
      ],
      { duration: 2100, delay: 900, easing: 'ease-in' },
    )
    this.later(() => this.trail(sl, 1900), 900)
    const hh = this.mk(
      `font-family:${SERIF};font-style:italic;font-size:20px;color:#f4f1ea;white-space:nowrap;`,
      'Ho ho ho!',
    )
    this.fly(
      hh,
      [
        { transform: 'translate(0,-70px) scale(0.6)', opacity: 0, offset: 0 },
        { transform: 'translate(0,-84px) scale(1)', opacity: 1, offset: 0.25 },
        { transform: 'translate(0,-92px) scale(1)', opacity: 1, offset: 0.7 },
        { transform: 'translate(0,-102px) scale(1)', opacity: 0, offset: 1 },
      ],
      { duration: 1500, delay: 1300, easing: 'ease-out' },
    )
    this.snowfall(18, 0, 1600)
    this.ring('#d9453f', 300)
    this.ring('#f2c94c', 1100)
    return D + 100
  }

  private d31(): number {
    const { swap, logo } = this.els
    const D = 2800
    this.setSwap(
      `<svg viewBox="0 0 88 88" width="88" height="88" aria-hidden="true" style="position:absolute;inset:0;"><rect x="3" y="3" width="82" height="82" rx="17" fill="none" stroke="#34405e" stroke-width="3"/><rect id="prog" x="3" y="3" width="82" height="82" rx="17" fill="none" stroke="#d9b44a" stroke-width="3" stroke-linecap="round" stroke-dasharray="300" stroke-dashoffset="300"/></svg><div id="num" style="position:relative;font-family:${SERIF};font-size:44px;line-height:1;color:#d8dde8;">31</div>`,
      '#222c45',
    )
    const num = this.q<HTMLElement>('#num')
    const prog = this.q('#prog')
    swap.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 1, offset: 0.12 },
        { opacity: 1, offset: 0.86 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D, fill: 'both' },
    )
    const nf = (sc: number, c: string, o: number, op = 1): Keyframe => ({
      transform: `scale(${sc})`,
      opacity: op,
      color: c,
      offset: o,
    })
    num.animate(
      [
        nf(0.9, '#d8dde8', 0, 0),
        nf(1, '#d8dde8', 0.16),
        nf(1.04, '#d8dde8', 0.35),
        nf(1, '#d8dde8', 0.5),
        nf(1.04, '#d8dde8', 0.6),
        nf(1.25, '#f2c94c', 0.66),
        nf(1, '#f2c94c', 0.76),
        nf(1, '#f2c94c', 1),
      ],
      { duration: D, fill: 'both' },
    )
    prog.animate([{ strokeDashoffset: 300 }, { strokeDashoffset: 0 }], {
      duration: 1500,
      delay: 300,
      easing: 'linear',
      fill: 'both',
    })
    logo.animate(
      [
        { transform: 'scale(1)', offset: 0 },
        { transform: 'scale(0.97)', offset: 0.25 },
        { transform: 'scale(0.97)', offset: 0.6 },
        { transform: 'scale(1.12)', offset: 0.67 },
        { transform: 'scale(1)', offset: 0.76 },
        { transform: 'scale(1)', offset: 1 },
      ],
      { duration: D, easing: 'ease-in-out' },
    )
    for (let i = 0; i < 16; i++) {
      const x = (i % 2 ? 1 : -1) * rnd(70, 170)
      let y = rnd(-120, 120)
      if (Math.abs(x) < 75 && Math.abs(y) < 60) y = y < 0 ? -70 : 70
      const s = Math.round(rnd(2, 4))
      const st = this.mk(
        `width:${s}px;height:${s}px;border-radius:50%;background:${pick(['#d9b44a', '#e8ecf5', '#b8c4e0'])};`,
      )
      this.fly(
        st,
        [
          { transform: `translate(${x}px,${y}px)`, opacity: 0, offset: 0 },
          { transform: `translate(${x}px,${y - 6}px)`, opacity: 0.9, offset: 0.5 },
          { transform: `translate(${x}px,${y - 12}px)`, opacity: 0, offset: 1 },
        ],
        { duration: Math.round(rnd(1400, 2000)), delay: Math.round(rnd(0, 1100)), easing: 'ease-in-out' },
      )
    }
    this.fw(
      [
        [-92, -52, 1750],
        [96, -64, 2000],
      ],
      ['#f2c94c', '#e8ecf5', '#9fd0f0'],
      12,
      26,
      44,
      '#f2c94c',
    )
    this.conf(18, 1850, 2100)
    this.ring('#d9b44a', 1800)
    return D + 100
  }

  private d1(): number {
    const { swap, logo, flash } = this.els
    const D = 3400
    const cols = ['#f2c94c', '#f2efe8', '#9fd0f0', '#f4b6c8', '#8fb58f']
    this.setSwap(
      `<div id="num" style="position:relative;display:flex;align-items:flex-start;font-family:${SERIF};color:#2d3f2d;line-height:1;"><span style="font-size:58px;">1</span><span style="font-size:26px;margin-top:9px;">º</span></div><div id="shine" style="position:absolute;top:-26px;left:0;width:16px;height:140px;background:#ffffff;opacity:0;transform:translateX(-30px) rotate(20deg);"></div><div id="hat" style="position:absolute;inset:0;opacity:0;">${HAT_PARTY}</div>`,
      '#f2c94c',
    )
    const num = this.q<HTMLElement>('#num')
    const shine = this.q<HTMLElement>('#shine')
    const hat = this.q<HTMLElement>('#hat')
    swap.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 1, offset: 0.03 },
        { opacity: 1, offset: 0.88 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D, fill: 'both' },
    )
    num.animate(
      [
        { transform: 'scale(0) rotate(-14deg)', offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: 'scale(1.35) rotate(6deg)', offset: 0.5 },
        { transform: 'scale(0.94) rotate(-2deg)', offset: 0.75 },
        { transform: 'scale(1) rotate(0deg)', offset: 1 },
      ],
      { duration: 520, fill: 'both' },
    )
    hat.animate(
      [
        { transform: 'translateY(-50px)', opacity: 0, offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: 'translateY(4px)', opacity: 1, offset: 0.6 },
        { transform: 'translateY(0)', opacity: 1, offset: 1 },
      ],
      { duration: 420, delay: 500, fill: 'both' },
    )
    const sweep: Frames = [
      { transform: 'translateX(-30px) rotate(20deg)', opacity: 0.55 },
      { transform: 'translateX(120px) rotate(20deg)', opacity: 0.55 },
    ]
    shine.animate(sweep, { duration: 500, delay: 700, fill: 'both' })
    shine.animate(sweep, { duration: 500, delay: 1700, fill: 'forwards' })
    const j = (y: number, sx: number, sy: number, o: number): Keyframe => ({
      transform: `translateY(${y}px) scale(${sx},${sy})`,
      offset: o,
    })
    logo.animate(
      [
        j(0, 1, 1, 0),
        j(-14, 0.98, 1.04, 0.05),
        j(0, 1.08, 0.92, 0.09),
        j(-10, 0.98, 1.04, 0.14),
        j(0, 1.06, 0.94, 0.18),
        j(-6, 1, 1, 0.22),
        j(0, 1, 1, 0.26),
        j(0, 1, 1, 0.4),
        j(-12, 0.98, 1.04, 0.46),
        j(0, 1.08, 0.92, 0.5),
        j(0, 1, 1, 0.56),
        j(0, 1, 1, 1),
      ],
      { duration: D, easing: 'ease-out' },
    )
    flash.style.background = '#f2c94c'
    flash.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 0.5, offset: 0.05 },
        { opacity: 0, offset: 0.15 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D },
    )
    this.fw(
      [
        [-112, -45, 150],
        [108, -62, 500],
        [-45, -100, 850],
        [55, -105, 1200],
        [0, 95, 1550],
      ],
      cols,
      18,
      40,
      70,
      '#f2c94c',
    )
    this.conf(56, 250, 800)
    this.rain(30, 700, 2000)
    const bc = ['#e9558f', '#2f80ed', '#f2c94c', '#3dbb6a', '#e2862c']
    for (let i = 0; i < 5; i++) {
      const x = -150 + i * 75 + rnd(-18, 18)
      const b = this.mk('width:26px;height:56px;', BAL(bc[i]!))
      this.fly(
        b,
        [
          { transform: `translate(${x}px,170px)`, opacity: 0, offset: 0 },
          { transform: `translate(${x}px,120px)`, opacity: 1, offset: 0.06 },
          { transform: `translate(${x + 14}px,-10px)`, opacity: 1, offset: 0.5 },
          { transform: `translate(${x - 12}px,-110px)`, opacity: 1, offset: 0.8 },
          { transform: `translate(${x + 6}px,-190px)`, opacity: 0.9, offset: 1 },
        ],
        { duration: 2100, delay: 400 + i * 220, easing: 'ease-in-out' },
      )
    }
    this.ring('#f2c94c', 150)
    this.ring('#e9558f', 1000)
    this.ring('#2f80ed', 1800)
    return D + 100
  }

  private carnaval(): number {
    const { swap, logo, flash } = this.els
    const D = 2500
    const el = this.scene(MASK, '#3a1f5c', D, 0.88)
    swap.animate(
      [
        { backgroundColor: '#3a1f5c' },
        { backgroundColor: '#5b2a86', offset: 0.25 },
        { backgroundColor: '#7a1f5c', offset: 0.5 },
        { backgroundColor: '#1f3a7a', offset: 0.75 },
        { backgroundColor: '#3a1f5c' },
      ],
      { duration: D },
    )
    const fr: Frames = [
      { transform: 'translateY(70px) rotate(-30deg) scale(0.5)', offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
      { transform: 'translateY(-6px) rotate(6deg) scale(1.1)', offset: 0.14 },
      { transform: 'translateY(0) rotate(0deg) scale(1)', offset: 0.2 },
    ]
    let o = 0.24
    for (let k = 0; k < 8; k++) {
      fr.push({
        transform: `translateY(${k % 2 ? 0 : -5}px) rotate(${k % 2 ? 9 : -9}deg) scale(${k % 2 ? 1 : 1.06})`,
        offset: o,
      })
      o += 0.075
    }
    fr.push(
      { transform: 'translateY(0) rotate(0deg) scale(1)', offset: 0.88 },
      { transform: 'translateY(0) rotate(0deg) scale(1)', offset: 1 },
    )
    el.animate(fr, { duration: D, fill: 'both' })
    this.q('#mk').animate(
      [
        { fill: '#f2c94c' },
        { fill: '#e9558f', offset: 0.25 },
        { fill: '#9fd0f0', offset: 0.5 },
        { fill: '#3dbb6a', offset: 0.75 },
        { fill: '#f2c94c' },
      ],
      { duration: 2000, delay: 300 },
    )
    ;[this.q('#g1'), this.q('#g2')].forEach((g, i) => {
      g.animate([{ opacity: 1 }, { opacity: 0.1 }], {
        duration: 200 + i * 60,
        delay: 400,
        iterations: 10,
        direction: 'alternate',
      })
    })
    this.q('#fe').style.transformOrigin = '70px 40px'
    this.q('#fe').animate([{ transform: 'rotate(-8deg)' }, { transform: 'rotate(8deg)' }], {
      duration: 300,
      delay: 400,
      iterations: 8,
      direction: 'alternate',
      easing: 'ease-in-out',
    })
    logo.animate(
      [
        { transform: 'rotate(0deg) scale(1)', offset: 0 },
        { transform: 'rotate(-6deg) scale(1.06)', offset: 0.2 },
        { transform: 'rotate(6deg) scale(1.06)', offset: 0.4 },
        { transform: 'rotate(-6deg) scale(1.06)', offset: 0.6 },
        { transform: 'rotate(0deg) scale(1)', offset: 0.8 },
        { transform: 'rotate(0deg) scale(1)', offset: 1 },
      ],
      { duration: 2200 },
    )
    const cols = ['#f2c94c', '#3dbb6a', '#2f80ed', '#e9558f', '#9b51e0', '#f2994a']
    for (let i = 0; i < 10; i++) {
      const h = Math.round(rnd(46, 90))
      const a = rnd(-Math.PI * 0.95, -Math.PI * 0.05)
      const d = rnd(90, 170)
      const dx = Math.cos(a) * d
      const dy = Math.sin(a) * d
      const fall = rnd(140, 200)
      const rot = rnd(-540, 540)
      const s = this.mk(`width:3px;height:${h}px;background:${pick(cols)};border-radius:2px;`)
      const end = `translate(${dx * 1.15}px,${dy + fall}px) rotate(${rot}deg)`
      this.fly(
        s,
        [
          { transform: 'translate(0,0) rotate(0deg)', opacity: 0, offset: 0, easing: 'cubic-bezier(.1,.7,.3,1)' },
          {
            transform: `translate(${dx}px,${dy}px) rotate(${rot * 0.4}deg)`,
            opacity: 1,
            offset: 0.35,
            easing: 'cubic-bezier(.4,0,.8,.6)',
          },
          { transform: end, opacity: 1, offset: 0.9 },
          { transform: end, opacity: 0, offset: 1 },
        ],
        { duration: 1600, delay: Math.round(rnd(150, 500)) },
      )
    }
    this.conf(24, 150, 450)
    this.conf(24, 1100, 1500)
    flash.style.background = '#f2c94c'
    flash.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 0.45, offset: 0.06 },
        { opacity: 0, offset: 0.2 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D },
    )
    this.ring('#f2c94c', 60)
    this.ring('#e9558f', 1200)
    return D + 300
  }

  private pascoa(): number {
    const { flash } = this.els
    const D = 2500
    const el = this.scene(BUNNY, '#bfe3cf', D, 0.88)
    const b = (y: string, sx: number, sy: number, o: number, easing?: string): Keyframe => ({
      transform: `translateY(${y}) scale(${sx},${sy})`,
      offset: o,
      ...(easing ? { easing } : {}),
    })
    el.animate(
      [
        b('100%', 1, 1, 0, 'cubic-bezier(.2,.8,.3,1)'),
        b('0', 1, 1, 0.2),
        b('-14px', 0.96, 1.06, 0.32, 'ease-in'),
        b('0', 1.08, 0.92, 0.42),
        b('-14px', 0.96, 1.06, 0.54, 'ease-in'),
        b('0', 1.08, 0.92, 0.64),
        b('0', 1, 1, 0.7),
        b('0', 1, 1, 0.78),
        b('100%', 1, 1, 0.92, 'ease-in'),
        b('100%', 1, 1, 1),
      ],
      { duration: D, fill: 'both' },
    )
    this.wob(this.q('#e1'), [-14, 8, -10, 6, -8, 0], 500, 170, '33px 42px')
    this.wob(this.q('#e2'), [12, -7, 10, -6, 8, 0], 560, 170, '55px 42px')
    for (const sel of ['#y1', '#y2']) {
      const e = this.q(sel)
      e.style.transformBox = 'fill-box'
      e.style.transformOrigin = '50% 50%'
      for (const dl of [900, 1500]) {
        e.animate([{ transform: 'scaleY(1)' }, { transform: 'scaleY(0.1)' }, { transform: 'scaleY(1)' }], {
          duration: 180,
          delay: dl,
        })
      }
    }
    const nz = this.q('#nz')
    nz.style.transformBox = 'fill-box'
    nz.style.transformOrigin = '50% 50%'
    nz.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.35)' }], {
      duration: 110,
      delay: 700,
      iterations: 10,
      direction: 'alternate',
    })
    const floor = this.mk(
      'left:0;right:0;bottom:0;height:18px;background:#6fb583;border-radius:10px 10px 0 0;transform-origin:50% 100%;',
    )
    this.fly(
      floor,
      [
        { transform: 'scaleY(0)', opacity: 1, offset: 0 },
        { transform: 'scaleY(1)', opacity: 1, offset: 0.1 },
        { transform: 'scaleY(1)', opacity: 1, offset: 0.92 },
        { transform: 'scaleY(1)', opacity: 0, offset: 1 },
      ],
      { duration: 2700, delay: 50 },
    )
    const pc = ['#f4b6c8', '#b9a7e8', '#a8dcc0', '#f6e08f', '#9fd0f0']
    for (let i = 0; i < 11; i++) {
      const w = Math.round(rnd(14, 20))
      const h = Math.round(w * 1.3)
      const c = pc[i % 5]
      const c2 = pc[(i + 2) % 5]
      const e = this.mk(
        `width:${w}px;height:${h}px;border-radius:50% 50% 50% 50% / 62% 62% 38% 38%;background:${c};overflow:hidden;`,
        `<div style="position:absolute;left:0;right:0;top:50%;height:3px;background:${c2};"></div>`,
      )
      this.toss(e, rnd(-125, 125), rnd(70, 115), rnd(112, 128), rnd(-200, 200), Math.round(rnd(550, 1100)), 1)
    }
    this.toss(this.mk('width:18px;height:36px;', CARROT), -100, 90, 112, -160, 900, 0.6)
    this.toss(this.mk('width:18px;height:36px;', CARROT), 105, 80, 112, 150, 1200, 0.6)
    const flies: [number, number, number, string, string][] = [
      [-1, -70, 400, '#e9558f', '#f4b6c8'],
      [1, -100, 1000, '#9b51e0', '#b9a7e8'],
    ]
    for (const [dir, y, dl, c1, c2] of flies) {
      const bf = this.mk('width:24px;height:20px;', `<div style="width:24px;height:20px;">${BFLY(c1, c2)}</div>`)
      ;(bf.firstChild as HTMLElement).animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0.35)' }], {
        duration: 110,
        delay: dl,
        iterations: 16,
        direction: 'alternate',
      })
      this.fly(
        bf,
        [
          { transform: `translate(${-dir * 200}px,${y + 20}px)`, opacity: 0, offset: 0 },
          { transform: `translate(${-dir * 120}px,${y - 16}px)`, opacity: 1, offset: 0.15 },
          { transform: `translate(${-dir * 30}px,${y + 14}px)`, opacity: 1, offset: 0.4 },
          { transform: `translate(${dir * 60}px,${y - 14}px)`, opacity: 1, offset: 0.65 },
          { transform: `translate(${dir * 210}px,${y + 6}px)`, opacity: 0, offset: 1 },
        ],
        { duration: 1800, delay: dl, easing: 'linear' },
      )
    }
    flash.style.background = '#f6e08f'
    flash.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 0.5, offset: 0.08 },
        { opacity: 0, offset: 0.25 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D },
    )
    this.ring('#b9a7e8', 300)
    this.ring('#6fb583', 1300)
    return D + 300
  }

  private namorados(): number {
    const D = 2500
    const el = this.scene(BIGHEART, '#b83a5a', D, 0.9)
    const sc = (s: string, o: number): Keyframe => ({ transform: `scale(${s})`, offset: o })
    el.animate(
      [
        { transform: 'scale(0.3) rotate(-10deg)', offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: 'scale(1.15) rotate(0deg)', offset: 0.1 },
        sc('1', 0.14),
        sc('1.12', 0.2),
        sc('1', 0.24),
        sc('1.1', 0.28),
        sc('1', 0.32),
        sc('1', 0.448),
        sc('0.86,1.1', 0.47),
        sc('1.14', 0.5),
        sc('0.96', 0.54),
        sc('1', 0.58),
        sc('1.14', 0.66),
        sc('1', 0.7),
        sc('1.12', 0.74),
        sc('1', 0.78),
        sc('1', 1),
      ],
      { duration: D, fill: 'both' },
    )
    const arw = this.q('#arw')
    arw.style.opacity = ''
    const a = (rot: number, x: number, op: number, o: number, easing?: string): Keyframe => ({
      transform: `translate(44px,46px) rotate(${rot}deg) translateX(${x}px)`,
      opacity: op,
      offset: o,
      ...(easing ? { easing } : {}),
    })
    arw.animate(
      [
        a(45, -80, 0, 0),
        a(45, -80, 0, 0.34),
        a(45, -70, 1, 0.35, 'cubic-bezier(.5,0,.9,.5)'),
        a(45, 0, 1, 0.448),
        a(49, 0, 1, 0.5),
        a(41, 0, 1, 0.54),
        a(45, 0, 1, 0.6),
        a(45, 0, 1, 1),
      ],
      { duration: D, fill: 'both' },
    )
    const cp = this.mk('width:44px;height:40px;', CUPID)
    this.fly(
      cp,
      [
        { transform: 'translate(-210px,-90px) scale(0.7)', opacity: 0, offset: 0 },
        { transform: 'translate(-92px,-82px) scale(1)', opacity: 1, offset: 0.25 },
        { transform: 'translate(-88px,-90px) scale(1)', opacity: 1, offset: 0.33 },
        { transform: 'translate(-92px,-84px) scale(1)', opacity: 1, offset: 0.42 },
        { transform: 'translate(-88px,-90px) scale(1)', opacity: 1, offset: 0.52 },
        { transform: 'translate(-60px,-110px) scale(1)', opacity: 1, offset: 0.62 },
        { transform: 'translate(60px,-130px) scale(0.8)', opacity: 0, offset: 1 },
      ],
      { duration: 2000, delay: 100, easing: 'ease-in-out' },
    )
    this.later(() => this.bump('#ff6f91'), 1120)
    for (let i = 0; i < 13; i++) {
      const sz = Math.round(rnd(14, 26))
      const sw = rnd(18, 46) * (i % 2 ? 1 : -1)
      const x0 = rnd(-30, 30)
      const rise = rnd(110, 140)
      const h = this.mk(
        `font-size:${sz}px;line-height:1;color:${pick(['#e9558f', '#f4b6c8', '#c0453f', '#f2efe8'])};`,
        HEART_ICON,
      )
      this.fly(
        h,
        [
          { transform: `translate(${x0}px,0) scale(0.3)`, opacity: 0, offset: 0 },
          { transform: `translate(${x0 + sw}px,${-rise * 0.45}px) scale(1)`, opacity: 1, offset: 0.3 },
          { transform: `translate(${x0 - sw * 0.6}px,${-rise * 0.8}px) scale(1)`, opacity: 1, offset: 0.7 },
          { transform: `translate(${x0 + sw * 0.4}px,${-rise}px) scale(0.9)`, opacity: 0, offset: 1 },
        ],
        { duration: 1500, delay: Math.round(rnd(1150, 1750)), easing: 'ease-out' },
      )
    }
    this.burst(8, 1120, ['#f4b6c8', '#f4f1ea', '#ff6f91'], 50, 90)
    this.ring('#e9558f', 1120)
    this.ring('#f4b6c8', 1800)
    return D + 300
  }

  private junino(): number {
    const { logo, flash } = this.els
    const D = 2700
    this.scene(BONFIRE, '#1c2447', D, 0.9)
    const fl = this.q('#fl')
    fl.style.transformOrigin = '44px 76px'
    fl.animate(
      [
        { transform: 'scale(0.2,0)', offset: 0, easing: 'cubic-bezier(.2,.8,.3,1)' },
        { transform: 'scale(1.15,1.2)', offset: 0.14 },
        { transform: 'scale(1,1)', offset: 0.2 },
        { transform: 'scale(1,1)', offset: 1 },
      ],
      { duration: D, fill: 'both' },
    )
    ;['#f1', '#f2', '#f3'].forEach((s, i) => {
      const f = this.q(s)
      f.style.transformOrigin = '44px 76px'
      f.animate(
        [
          { transform: 'scale(1,1) skewX(0deg)' },
          { transform: `scale(${0.93 - i * 0.02},${1.1 + i * 0.04}) skewX(${i % 2 ? 4 : -4}deg)` },
        ],
        {
          duration: 150 + i * 55,
          delay: 450,
          iterations: Math.round(2000 / (150 + i * 55)),
          direction: 'alternate',
          easing: 'ease-in-out',
        },
      )
    })
    this.els.swap.querySelectorAll('.st').forEach((s, i) => {
      s.animate([{ opacity: 1 }, { opacity: 0.2 }], { duration: 300 + i * 90, iterations: 12, direction: 'alternate' })
    })
    const cols = ['#e9558f', '#f2c94c', '#3dbb6a', '#2f80ed', '#e2862c', '#9b51e0']
    const n = 10
    const line = this.mk('left:0;right:0;top:12px;height:2px;background:#c9a56a;')
    this.fly(
      line,
      [
        { opacity: 0, offset: 0 },
        { opacity: 0.9, offset: 0.1 },
        { opacity: 0.9, offset: 0.88 },
        { opacity: 0, offset: 1 },
      ],
      { duration: 2700 },
    )
    for (let i = 0; i < n; i++) {
      const f = this.mk(
        `left:${((i + 0.5) / n) * 100}%;margin-left:-10px;top:13px;width:0;height:0;border-left:10px solid transparent;border-right:10px solid transparent;border-top:24px solid ${cols[i % cols.length]};transform-origin:50% 0;`,
      )
      const r = (deg: number, o: number, op = 1): Keyframe => ({
        transform: `translateY(0) rotate(${deg}deg)`,
        opacity: op,
        offset: o,
      })
      this.fly(
        f,
        [
          { transform: 'translateY(-40px) rotate(0deg)', opacity: 0, offset: 0 },
          r(0, 0.1),
          r(7, 0.25),
          r(-7, 0.4),
          r(5, 0.55),
          r(-4, 0.7),
          r(0, 0.88),
          r(0, 1, 0),
        ],
        { duration: 2600, delay: i * 70, easing: 'ease-out' },
      )
    }
    const balloons: [number, string, number][] = [
      [-105, '#e9558f', 200],
      [110, '#f2c94c', 500],
      [-30, '#3dbb6a', 850],
      [45, '#e2862c', 1150],
    ]
    for (const [x, c, dl] of balloons) {
      const bl = this.mk('width:28px;height:44px;', PBAL(c))
      this.fly(
        bl,
        [
          { transform: `translate(${x}px,170px) scale(0.8)`, opacity: 0, offset: 0 },
          { transform: `translate(${x + 12}px,90px) scale(0.9)`, opacity: 1, offset: 0.2 },
          { transform: `translate(${x - 10}px,0px) scale(1)`, opacity: 1, offset: 0.5 },
          { transform: `translate(${x + 12}px,-90px) scale(1)`, opacity: 1, offset: 0.8 },
          { transform: `translate(${x - 6}px,-170px) scale(1)`, opacity: 0, offset: 1 },
        ],
        { duration: 2100, delay: dl, easing: 'ease-in-out' },
      )
    }
    for (let k = 0; k < 24; k++) {
      const s = Math.round(rnd(3, 5))
      const x = rnd(-16, 16)
      const y0 = rnd(10, 34)
      const rise = rnd(110, 190)
      const sp = this.mk(
        `z-index:3;width:${s}px;height:${s}px;border-radius:50%;background:${pick(['#e2862c', '#f2c94c', '#f2994a', '#c0453f'])};`,
      )
      this.fly(
        sp,
        [
          { transform: `translate(${x}px,${y0}px)`, opacity: 0, offset: 0 },
          { transform: `translate(${x + rnd(-18, 18)}px,${y0 - rise * 0.4}px)`, opacity: 1, offset: 0.25 },
          { transform: `translate(${x + rnd(-30, 30)}px,${y0 - rise * 0.75}px)`, opacity: 0.8, offset: 0.7 },
          { transform: `translate(${x + rnd(-40, 40)}px,${y0 - rise}px)`, opacity: 0, offset: 1 },
        ],
        { duration: 1100, delay: Math.round(rnd(250, 1900)), easing: 'ease-out' },
      )
    }
    this.fw(
      [
        [-95, -72, 1500],
        [100, -88, 1900],
        [5, -112, 2300],
      ],
      ['#f2c94c', '#e9558f', '#9fd0f0', '#f4f1ea'],
      14,
      30,
      60,
      '#f2c94c',
    )
    logo.animate(
      [
        { transform: 'scale(1)', offset: 0 },
        { transform: 'scale(1.06)', offset: 0.1 },
        { transform: 'scale(1)', offset: 0.2 },
        { transform: 'scale(1.04)', offset: 0.4 },
        { transform: 'scale(1)', offset: 0.6 },
        { transform: 'scale(1)', offset: 1 },
      ],
      { duration: 1800 },
    )
    flash.style.background = '#e2862c'
    flash.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 0.5, offset: 0.1 },
        { opacity: 0, offset: 0.25 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D },
    )
    this.ring('#e2862c', 400)
    return D + 300
  }

  private dev(): number {
    const { swap, logo, flash } = this.els
    const D = 1800
    const chars = '01{}<>/;=()[]&|'
    this.setSwap(TAG, '#1e2d1e')
    swap.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 1, offset: 0.1 },
        { opacity: 0.3, offset: 0.14 },
        { opacity: 1, offset: 0.18 },
        { opacity: 0.5, offset: 0.22 },
        { opacity: 1, offset: 0.26 },
        { opacity: 1, offset: 0.6 },
        { opacity: 0, offset: 0.7 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D, fill: 'both' },
    )
    logo.animate(
      [
        { transform: 'scale(1)', offset: 0 },
        { transform: 'scale(1.1)', offset: 0.18 },
        { transform: 'scale(1)', offset: 0.3 },
        { transform: 'scale(1)', offset: 1 },
      ],
      { duration: D, easing: 'ease-out' },
    )
    const cols = 16
    for (let i = 0; i < cols; i++) {
      const len = 5 + Math.floor(rnd(0, 3))
      let html = ''
      for (let j = 0; j < len; j++) {
        const ch = chars.charAt(Math.floor(Math.random() * chars.length)).replace('<', '&lt;').replace('>', '&gt;')
        html += `<div style="opacity:${0.25 + (0.75 * j) / (len - 1)}${j === len - 1 ? ';color:#cfe8cf' : ''}">${ch}</div>`
      }
      const c = this.mk(
        `left:${((i + 0.5) / cols) * 100}%;margin-left:-4px;top:0;font-family:${MONO};font-size:13px;line-height:15px;color:#6f9a6f;text-align:center;`,
        html,
      )
      this.fly(
        c,
        [
          { transform: 'translateY(-110px)', opacity: 0, offset: 0 },
          { transform: 'translateY(10px)', opacity: 1, offset: 0.15 },
          { transform: 'translateY(160px)', opacity: 0.9, offset: 0.7 },
          { transform: 'translateY(300px)', opacity: 0, offset: 1 },
        ],
        { duration: rnd(1100, 1500), delay: Math.round(rnd(0, 500)), easing: 'linear' },
      )
    }
    flash.style.background = '#9cc29c'
    flash.animate(
      [
        { opacity: 0, offset: 0 },
        { opacity: 0, offset: 0.6 },
        { opacity: 0.5, offset: 0.68 },
        { opacity: 0, offset: 0.85 },
        { opacity: 0, offset: 1 },
      ],
      { duration: D },
    )
    this.ring('#6f9a6f', 900)
    return D + 300
  }
}
