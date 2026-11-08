<script lang="ts">
  import { safeUrl } from '../../stores/inline'

  interface Props {
    url: string
    title: string
    /** What the address field says while it is empty. */
    hint?: string
    /** Called with a checked address. The form closes itself only when this returns true. */
    onsave: (url: string, title: string) => boolean
    onerror: (message: string) => void
  }

  let { url: initialUrl, title: initialTitle, hint = 'https://…', onsave, onerror }: Props = $props()

  // svelte-ignore state_referenced_locally
  let url = $state(initialUrl)
  // svelte-ignore state_referenced_locally
  let title = $state(initialTitle)

  function submit(e: SubmitEvent) {
    e.preventDefault()
    if (!safeUrl(url)) return onerror('Endereço inválido: use http, https ou e-mail')
    if (!onsave(url, title)) onerror('Este endereço não serve para este bloco: use http ou https')
  }
</script>

<form class="flex flex-col gap-2 rounded-field border border-line p-3 sm:flex-row sm:items-center" onsubmit={submit}>
  <input bind:value={url} aria-label="Endereço do link" placeholder={hint} maxlength="2000" inputmode="url" autocomplete="off" class="h-9 min-w-0 flex-1 rounded border border-field-line bg-bg px-2 text-sm placeholder:text-muted" />
  <input bind:value={title} aria-label="Título do link (opcional)" placeholder="Título (opcional)" maxlength="200" class="h-9 min-w-0 flex-1 rounded border border-field-line bg-bg px-2 text-sm placeholder:text-muted" />
  <button type="submit" class="h-9 rounded-field bg-cream px-4 text-sm font-medium text-on-cream">Salvar</button>
</form>
