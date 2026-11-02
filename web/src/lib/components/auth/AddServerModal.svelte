<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { ms } from '../../motion'
  import { MAX_INPUT_LENGTH, MAX_NAME_LENGTH } from '../../api/serverCheck'
  import { manual } from '../../stores/manual.svelte'
  import { toast } from '../../stores/toast.svelte'

  interface Props {
    onclose: () => void
  }

  let { onclose }: Props = $props()

  let address = $state('')
  let name = $state('')
  let error = $state('')
  let busy = $state(false)
  let controller: AbortController | undefined

  function focusOnMount(node: HTMLElement) {
    node.focus()
  }

  function close() {
    controller?.abort() // a check in flight must not add a server after the window is gone
    onclose()
  }

  async function submit(e: SubmitEvent) {
    e.preventDefault()
    if (busy) return
    busy = true
    error = ''
    controller = new AbortController()
    const result = await manual.add(address, name, controller.signal)
    if (controller.signal.aborted) return
    busy = false
    if (result.ok) {
      toast.show(`${result.server.name} adicionado.`)
      onclose()
    } else {
      error = result.error
    }
  }

  const input =
    'h-13 w-full rounded-field border border-line bg-bg px-4 text-fg placeholder:text-muted/60 focus:border-accent-line focus:outline-none disabled:opacity-60'
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && close()} />

<div
  class="fixed inset-0 z-30 flex items-end justify-center bg-black/60 sm:items-center"
  data-testid="add-server-overlay"
  transition:fade|global={{ duration: ms(200) }}
>
  <button type="button" aria-label="Fechar" class="absolute inset-0 cursor-default" onclick={close}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-labelledby="add-server-title"
    transition:fly|global={{ y: 80, duration: ms(250) }}
    class="relative max-h-full w-full max-w-md overflow-y-auto rounded-t-3xl border border-line bg-surface p-6 sm:rounded-3xl"
  >
    <form novalidate onsubmit={submit}>
    <h2 id="add-server-title" class="font-serif text-2xl">Adicionar servidor</h2>
    <p class="mt-2 leading-[1.4] text-muted">
      Digite o endereço de um servidor Plany: um IP, como 192.168.0.20:8095, ou um domínio. Sem http:// ou https://,
      testo os dois.
    </p>
    <label class="mt-4 block font-mono text-[11px] tracking-[1px] text-muted uppercase" for="add-server-address">
      Endereço
    </label>
    <input
      id="add-server-address"
      use:focusOnMount
      bind:value={address}
      maxlength={MAX_INPUT_LENGTH}
      disabled={busy}
      inputmode="url"
      autocomplete="off"
      autocapitalize="off"
      spellcheck="false"
      placeholder="meu.servidor.com"
      class="{input} mt-1.5"
    />
    <label class="mt-4 block font-mono text-[11px] tracking-[1px] text-muted uppercase" for="add-server-name">
      Nome (opcional)
    </label>
    <input
      id="add-server-name"
      bind:value={name}
      maxlength={MAX_NAME_LENGTH}
      disabled={busy}
      autocomplete="off"
      placeholder="Usar o nome do servidor"
      class="{input} mt-1.5"
    />
    {#if error}
      <p role="alert" class="mt-3 text-sm leading-[1.4] break-words text-offline">{error}</p>
    {/if}
    <div class="mt-5 flex flex-col gap-3 sm:flex-row-reverse">
      <button
        type="submit"
        disabled={busy}
        class="h-13 w-full rounded-field bg-cream font-semibold text-on-cream transition duration-150 hover:bg-cream/90 active:scale-[0.98] disabled:opacity-60"
      >
        {busy ? 'Verificando…' : 'Adicionar'}
      </button>
      <button
        type="button"
        onclick={close}
        class="h-13 w-full rounded-field border border-line font-mono text-xs tracking-[0.6px] text-muted uppercase transition-colors duration-150 hover:text-fg"
      >
        Cancelar
      </button>
    </div>
    </form>
  </div>
</div>
