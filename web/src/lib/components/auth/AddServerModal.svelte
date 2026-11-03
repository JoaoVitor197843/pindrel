<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { ms } from '../../motion'
  import { modal } from '../../a11y/dialog'
  import { MAX_INPUT_LENGTH, MAX_NAME_LENGTH } from '../../api/serverCheck'
  import { manual } from '../../stores/manual.svelte'
  import { toast } from '../../stores/toast.svelte'

  interface Props {
    onclose: () => void
  }

  let { onclose }: Props = $props()

  // who had the focus when this opened: the dialog gives it back there when it closes
  const opener = document.activeElement

  let address = $state('')
  let name = $state('')
  let error = $state('')
  let busy = $state(false)
  // a wait that goes on is said out loud, once: silence reads as "frozen"
  let slow = $state(false)
  let controller: AbortController | undefined
  let addressField: HTMLInputElement | undefined = $state()
  let slowTimer: ReturnType<typeof setTimeout> | undefined

  function focusOnMount(node: HTMLElement) {
    node.focus()
  }

  // closing by any route (also the page going away) must not leave a check that adds a server behind it
  $effect(() => () => {
    controller?.abort()
    clearTimeout(slowTimer)
  })

  function close() {
    controller?.abort()
    onclose()
  }

  /** Escape stops a check in flight first (the window stays, the text is kept); only then does it close. */
  function escape() {
    if (busy) controller?.abort()
    else close()
  }

  /** A click beside the window closes it only when there is nothing typed to lose. */
  function backdrop() {
    if (!busy && !address.trim() && !name.trim()) close()
  }

  async function submit(e: SubmitEvent) {
    e.preventDefault()
    if (busy) return
    busy = true
    slow = false
    error = ''
    slowTimer = setTimeout(() => (slow = true), 2500)
    const mine = (controller = new AbortController())
    const result = await manual.add(address, name, mine.signal)
    clearTimeout(slowTimer)
    busy = false
    slow = false
    if (mine.signal.aborted) {
      // stopped by Escape or closed: nothing to say, the focus goes back to where the person was typing
      addressField?.focus()
      return
    }
    if (result.ok) {
      toast.show(`${result.server.name} adicionado.`)
      onclose()
    } else {
      error = result.error
      // the field that needs fixing, so the next keystroke already corrects it (a disabled control would have dropped the focus)
      addressField?.focus()
    }
  }

  const input =
    'h-13 w-full rounded-field border border-field-line bg-bg px-4 text-fg placeholder:text-muted focus:border-accent-line read-only:opacity-60'
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && escape()} />

<div
  class="fixed inset-0 z-30 flex items-end justify-center bg-black/60 sm:items-center"
  data-testid="add-server-overlay"
  transition:fade|global={{ duration: ms(200) }}
>
  <!-- a mouse convenience only: the keyboard has Escape and "Cancelar", so it is out of the tab order and the reading -->
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="backdrop" class="absolute inset-0 cursor-default" onclick={backdrop}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-labelledby="add-server-title"
    aria-describedby="add-server-help"
    use:modal={opener}
    transition:fly|global={{ y: 80, duration: ms(250) }}
    class="relative max-h-full w-full max-w-md overflow-y-auto rounded-t-3xl border border-line bg-surface p-6 sm:rounded-3xl"
  >
    <form novalidate onsubmit={submit} aria-busy={busy}>
      <h2 id="add-server-title" class="font-serif text-2xl">Adicionar servidor</h2>
      <p id="add-server-help" class="mt-2 leading-[1.4] text-muted">
        Digite o endereço de um servidor Pindrel: um IP, como 192.168.0.20:8095, ou um domínio. Sem http:// ou https://,
        testo os dois.
      </p>
      <!-- captions are paragraphs tied by aria-labelledby (not <label>): a screen reader reads the dialog's text in one
           go and paragraphs keep "Endereço" and "Nome" apart -->
      <p id="add-server-address-label" class="mt-4 font-mono text-[11px] tracking-[1px] text-muted uppercase">Endereço</p>
      <input
        id="add-server-address"
        aria-labelledby="add-server-address-label"
        use:focusOnMount
        bind:this={addressField}
        bind:value={address}
        oninput={() => (error = '')}
        maxlength={MAX_INPUT_LENGTH}
        readonly={busy}
        aria-invalid={error ? 'true' : undefined}
        aria-describedby={error ? 'add-server-error' : undefined}
        aria-required="true"
        inputmode="url"
        enterkeyhint="go"
        autocomplete="off"
        autocapitalize="off"
        spellcheck="false"
        placeholder="meu.servidor.com"
        class="{input} mt-1.5"
      />
      <p id="add-server-name-label" class="mt-4 font-mono text-[11px] tracking-[1px] text-muted uppercase">Nome (opcional)</p>
      <input
        id="add-server-name"
        aria-labelledby="add-server-name-label"
        bind:value={name}
        maxlength={MAX_NAME_LENGTH}
        readonly={busy}
        enterkeyhint="go"
        autocomplete="off"
        placeholder="Usar o nome do servidor"
        class="{input} mt-1.5"
      />
      {#if error}
        <p id="add-server-error" role="alert" class="mt-3 text-sm leading-[1.4] break-words text-offline-text">{error}</p>
      {/if}
      <!-- announced politely while the check runs; the button text alone is not read when focus stays on it -->
      <p role="status" class="sr-only">{busy ? (slow ? 'Ainda verificando o endereço…' : 'Verificando o endereço…') : ''}</p>
      <div class="mt-5 flex flex-col gap-3 sm:flex-row-reverse">
        <button
          type="submit"
          aria-disabled={busy}
          class="h-13 w-full rounded-field bg-cream font-semibold text-on-cream transition duration-150 hover:bg-cream/90 active:scale-[0.98] aria-disabled:opacity-60"
        >
          {busy ? (slow ? 'Ainda verificando…' : 'Verificando…') : 'Adicionar'}
        </button>
        <button
          type="button"
          onclick={close}
          class="h-13 w-full rounded-field border border-field-line font-mono text-xs tracking-[0.6px] text-muted uppercase transition-colors duration-150 hover:text-fg"
        >
          Cancelar
        </button>
      </div>
    </form>
  </div>
</div>
