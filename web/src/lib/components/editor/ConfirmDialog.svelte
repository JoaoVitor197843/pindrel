<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { modal } from '../../a11y/dialog'
  import { ms } from '../../motion'

  interface Props {
    title: string
    body: string
    confirmLabel: string
    /** The confirmation is for something that cannot be undone. */
    danger?: boolean
    onconfirm: () => void
    oncancel: () => void
  }

  let { title, body, confirmLabel, danger = false, onconfirm, oncancel }: Props = $props()

  const opener = document.activeElement

  // the safe answer has the focus: pressing Enter by reflex cancels
  function focusOnMount(node: HTMLElement) {
    node.focus()
  }
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && oncancel()} />

<div class="fixed inset-0 z-[70] flex items-end justify-center sm:items-center" transition:fade|global={{ duration: ms(200) }}>
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="confirm-backdrop" class="absolute inset-0 cursor-default bg-black/60" onclick={oncancel}></button>
  <div
    role="alertdialog"
    aria-modal="true"
    aria-labelledby="confirm-title"
    aria-describedby="confirm-body"
    use:modal={opener}
    transition:fly|global={{ y: 60, duration: ms(220) }}
    class="relative w-full max-w-md rounded-t-3xl border border-line bg-surface p-6 sm:rounded-3xl"
  >
    <h2 id="confirm-title" class="font-serif text-2xl">{title}</h2>
    <p id="confirm-body" class="mt-2 leading-[1.45] text-muted">{body}</p>
    <div class="mt-5 flex flex-col gap-3 sm:flex-row-reverse">
      <button type="button" use:focusOnMount class="h-12 w-full rounded-field bg-cream font-semibold text-on-cream hover:bg-cream/90" onclick={oncancel}>Cancelar</button>
      <button
        type="button"
        class="h-12 w-full rounded-field border px-4 text-sm font-medium {danger ? 'border-offline text-offline-text hover:bg-offline/10' : 'border-field-line text-fg hover:bg-line/40'}"
        onclick={onconfirm}
      >
        {confirmLabel}
      </button>
    </div>
  </div>
</div>
