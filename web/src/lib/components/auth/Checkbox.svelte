<script lang="ts">
  import { untrack } from 'svelte'
  import { easeIn, easeOut } from '../../animation'
  import { ms } from '../../motion'

  interface Props {
    checked: boolean
  }

  let { checked }: Props = $props()

  // O Checkbox do Material, refeito: 18 px, 200 ms, `easeIn` ao marcar e `easeOut` ao desmarcar. Uma posição
  // `t` de 0 a 1 guia tudo: até 0,5 a caixa encolhe 1 px por lado e o preenchimento aparece (nos primeiros
  // 25%); depois ela volta ao tamanho e o "certo" é traçado, primeiro a perna curta e depois a longa.
  // Desmarcar toca o mesmo caminho ao contrário, a partir de onde estiver.
  const SIZE = 18
  const DURATION_MS = 200
  const START = [SIZE * 0.15, SIZE * 0.45]
  const MID = [SIZE * 0.4, SIZE * 0.7]
  const END = [SIZE * 0.85, SIZE * 0.25]

  const initial = untrack(() => (checked ? 1 : 0))
  let t = $state(initial)
  // o valor linear (antes da curva): é dele que a animação parte se for interrompida
  let controller = initial
  let frame = 0

  $effect(() => {
    const target = checked ? 1 : 0
    untrack(() => run(target))
    return () => cancelAnimationFrame(frame)
  })

  function run(target: number) {
    cancelAnimationFrame(frame)
    const from = controller
    const total = ms(DURATION_MS) * Math.abs(target - from)
    if (total <= 0 || from === target) {
      controller = target
      t = target
      return
    }
    const curve = target === 1 ? easeIn : easeOut
    const began = performance.now()
    const step = (now: number) => {
      const done = Math.min(1, (now - began) / total)
      controller = from + (target - from) * done
      t = curve(controller)
      if (done < 1) frame = requestAnimationFrame(step)
    }
    frame = requestAnimationFrame(step)
  }

  const inset = $derived(1 - Math.abs(t - 0.5) * 2)
  const side = $derived(SIZE - inset * 2)
  const fill = $derived(t >= 0.25 ? 1 : t * 4)

  const n = (v: number) => Math.round(v * 100) / 100
  const lerp = (a: number[], b: number[], k: number) => [n(a[0] + (b[0] - a[0]) * k), n(a[1] + (b[1] - a[1]) * k)]
  const check = $derived.by(() => {
    if (t <= 0.5) return ''
    const k = (t - 0.5) * 2
    if (k < 0.5) {
      const p = lerp(START, MID, k * 2)
      return `M${n(START[0])} ${n(START[1])}L${p[0]} ${p[1]}`
    }
    const p = lerp(MID, END, (k - 0.5) * 2)
    return `M${n(START[0])} ${n(START[1])}L${n(MID[0])} ${n(MID[1])}L${p[0]} ${p[1]}`
  })
</script>

<svg width={SIZE} height={SIZE} viewBox="0 0 {SIZE} {SIZE}" aria-hidden="true" data-testid="checkbox-box" data-t={t.toFixed(3)}>
  <rect x={inset} y={inset} width={side} height={side} rx="4" class="fill-accent" fill-opacity={fill} />
  <rect x={inset + 0.5} y={inset + 0.5} width={side - 1} height={side - 1} rx="3.5" fill="none" class="stroke-accent-line" />
  <path d={check} fill="none" class="stroke-fg" stroke-width="2" />
</svg>
