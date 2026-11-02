<script lang="ts">
  import { onDestroy } from 'svelte'
  import { ms } from '../../motion'
  import { playLogoScene, type Playing } from '../../logo/play'
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

  function onclick() {
    const result = trigger.tap()
    if (result === 'press') press()
    if (result !== 'fire') return
    playing = playLogoScene(theme ?? currentTheme(new Date(), undefined, region), button)
    trigger.hold(playing.duration)
  }

  // an app sent to the background does not keep a scene running
  function onvisibilitychange() {
    if (!document.hidden) return
    playing?.cancel()
    trigger.release()
  }

  onDestroy(() => {
    playing?.cancel()
    trigger.release()
  })
</script>

<svelte:document {onvisibilitychange} />

<button
  bind:this={button}
  type="button"
  {onclick}
  aria-label="Logo do Pindrel"
  class="flex size-9 shrink-0 cursor-default items-center justify-center rounded-lg bg-accent font-serif text-xl select-none [-webkit-tap-highlight-color:transparent]"
>
  P
</button>
