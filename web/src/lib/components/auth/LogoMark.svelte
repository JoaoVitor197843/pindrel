<script lang="ts">
  import { onDestroy } from 'svelte'
  import { ms } from '../../motion'
  import type { Playing } from '../../logo/play'
  import { currentTheme, type LogoTheme } from '../../logo/season'
  import { TapTrigger } from '../../logo/trigger'

  interface Props {
    /** ISO country code whose own dates apply (see `regionalRules`); none by default. */
    region?: string
    /** Plays this theme instead of the one of the day (tests). */
    theme?: LogoTheme
  }

  let { region, theme }: Props = $props()

  const trigger = new TapTrigger()
  let button: HTMLButtonElement
  let playing: Playing | undefined

  function press() {
    // `ms` is 0 with "reduce motion" on or without Web Animations
    if (ms(140) > 0) button.animate([{ transform: 'scale(1)' }, { transform: 'scale(0.92)' }, { transform: 'scale(1)' }], { duration: 140, easing: 'ease-out' })
  }

  // The scenes are ~60 KB of code that runs once a year at most: a separate chunk, fetched from the first tap so it is
  // there by the fifth, instead of weighing on every page load.
  let scenes: Promise<typeof import('../../logo/play')> | undefined
  const loadScenes = () => (scenes ??= import('../../logo/play'))
  let gone = false

  // while the chunk is still arriving taps must not queue up scenes
  const LOADING_HOLD_MS = 15_000

  async function fire() {
    trigger.hold(LOADING_HOLD_MS)
    try {
      const { playLogoScene } = await loadScenes()
      if (gone || document.hidden) return trigger.release()
      playing = playLogoScene(theme ?? currentTheme(new Date(), undefined, region), button)
      trigger.hold(playing.duration)
    } catch {
      // chunk unreachable (offline, server switched): the logo is decoration, nothing to report
      scenes = undefined
      trigger.release()
    }
  }

  function onclick() {
    const result = trigger.tap()
    if (result === 'press') {
      press()
      void loadScenes().catch(() => (scenes = undefined))
    }
    if (result === 'fire') void fire()
  }

  // an app sent to the background does not keep a scene running
  function onvisibilitychange() {
    if (!document.hidden) return
    playing?.cancel()
    trigger.release()
  }

  onDestroy(() => {
    gone = true
    playing?.cancel()
    trigger.release()
  })
</script>

<svelte:document {onvisibilitychange} />

<!-- A touch/click easter egg: out of the tab order and the reading, so a keyboard or screen-reader user meets no dead button -->
<button
  bind:this={button}
  type="button"
  {onclick}
  tabindex="-1"
  aria-hidden="true"
  data-testid="logo-mark"
  class="flex size-9 shrink-0 cursor-default items-center justify-center rounded-lg bg-accent font-serif text-xl select-none [-webkit-tap-highlight-color:transparent]"
>
  P
</button>
