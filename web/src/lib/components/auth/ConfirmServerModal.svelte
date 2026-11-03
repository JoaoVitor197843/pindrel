<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { ms } from '../../motion'
  import { modal } from '../../a11y/dialog'

  interface Props {
    name: string
    onconfirm: () => void
    oncancel: () => void
  }

  let { name, onconfirm, oncancel }: Props = $props()

  // who had the focus when this opened: the dialog gives it back there when it closes
  const opener = document.activeElement

  // the safe answer has the focus: pressing Enter by reflex cancels
  function focusOnMount(node: HTMLElement) {
    node.focus()
  }
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && oncancel()} />

<div
  class="fixed inset-0 z-30 flex items-end justify-center bg-black/60 sm:items-center"
  data-testid="confirm-server-overlay"
  transition:fade|global={{ duration: ms(200) }}
>
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="backdrop" class="absolute inset-0 cursor-default" onclick={oncancel}></button>
  <div
    role="alertdialog"
    aria-modal="true"
    aria-labelledby="confirm-server-title"
    aria-describedby="confirm-server-text"
    use:modal={opener}
    transition:fly|global={{ y: 80, duration: ms(250) }}
    class="relative max-h-full w-full max-w-md overflow-y-auto rounded-t-3xl border border-line bg-surface p-6 sm:rounded-3xl"
  >
    <h2 id="confirm-server-title" class="font-serif text-2xl">Este servidor mudou</h2>
    <p id="confirm-server-text" class="mt-2 leading-[1.4] break-words text-muted">
      O que responde como “{name}” não é o mesmo servidor que você abriu antes. Pode ser um servidor novo com o mesmo
      nome, ou outro aparelho da rede se passando por ele. Só continue se você o reconhece: ele verá a senha que você
      digitar.
    </p>
    <div class="mt-5 flex flex-col gap-3 sm:flex-row-reverse">
      <button
        type="button"
        use:focusOnMount
        onclick={oncancel}
        class="h-13 w-full rounded-field bg-cream font-semibold text-on-cream transition duration-150 hover:bg-cream/90 active:scale-[0.98]"
      >
        Cancelar
      </button>
      <button
        type="button"
        onclick={onconfirm}
        class="h-13 w-full rounded-field border border-field-line font-mono text-xs tracking-[0.6px] text-muted uppercase transition-colors duration-150 hover:text-fg"
      >
        Continuar mesmo assim
      </button>
    </div>
  </div>
</div>
