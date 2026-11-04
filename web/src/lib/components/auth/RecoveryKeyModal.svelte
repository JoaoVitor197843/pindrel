<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { ms } from '../../motion'
  import { modal } from '../../a11y/dialog'
  interface Props {
    onclose: () => void
  }

  let { onclose }: Props = $props()

  // who had the focus when this opened: the dialog gives it back there when it closes
  const opener = document.activeElement

  // Virtual keyboard: what it covers of the window becomes space at the bottom, so the field and the button rise together
  // (the app's `viewInsets.bottom`). Without `visualViewport` (or without a keyboard) the gap is zero.
  let keyboard = $state(0)

  $effect(() => {
    const viewport = window.visualViewport
    if (!viewport) return
    const update = () => {
      keyboard = Math.max(0, Math.round(window.innerHeight - viewport.height - viewport.offsetTop))
    }
    update()
    viewport.addEventListener('resize', update)
    viewport.addEventListener('scroll', update)
    return () => {
      viewport.removeEventListener('resize', update)
      viewport.removeEventListener('scroll', update)
    }
  })
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && onclose()} />

<div
  class="fixed inset-0 z-30 flex items-end justify-center bg-black/60 sm:items-center"
  style="padding-bottom: {keyboard}px"
  data-testid="recovery-overlay"
  transition:fade|global={{ duration: ms(200) }}
>
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="backdrop" class="absolute inset-0 cursor-default" onclick={onclose}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-labelledby="recovery-title"
    use:modal={opener}
    transition:fly|global={{ y: 80, duration: ms(250) }}
    class="relative max-h-full w-full max-w-md overflow-y-auto rounded-t-3xl border border-line bg-surface p-6 sm:rounded-3xl"
  >
    <h2 id="recovery-title" class="font-serif text-2xl">Chave de recuperação</h2>
    <p class="mt-2 leading-[1.4] text-muted">Digite o código de recuperação gerado quando você criou a conta.</p>
    <label for="recovery-code" class="sr-only">Código de recuperação</label>
    <input
      id="recovery-code"
      type="text"
      autocomplete="off"
      placeholder="XXXX-XXXX-XXXX"
      class="mt-4 w-full rounded-field border border-field-line bg-surface px-4 py-4 font-mono tracking-[2px] uppercase placeholder:text-muted transition-colors duration-200 focus:border-accent-line focus:outline-none"
    />
    <button
      type="button"
      onclick={onclose}
      class="mt-4 h-13 w-full rounded-field bg-cream font-semibold text-on-cream transition duration-150 hover:bg-cream/90 active:scale-[0.98]"
    >
      Recuperar acesso
    </button>
  </div>
</div>
