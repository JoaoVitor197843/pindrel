<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { modal } from '../../a11y/dialog'
  import { ms } from '../../motion'
  import { MIN_VAULT_PASSWORD } from '../../stores/workspace.svelte'
  import Icon from './Icon.svelte'

  interface Props {
    /** What is being opened: shown in the sentence ("uma nova entrada", a title). */
    target: string
    /** Returns false when the password was refused. */
    onunlock: (password: string) => boolean
    onclose: () => void
  }

  let { target, onunlock, onclose }: Props = $props()

  const opener = document.activeElement
  let password = $state('')
  let error = $state('')

  function submit(e: SubmitEvent) {
    e.preventDefault()
    if (!onunlock(password)) error = `senha muito curta — mínimo ${MIN_VAULT_PASSWORD} caracteres`
    password = ''
  }

  function focusOnMount(node: HTMLElement) {
    node.focus()
  }
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && onclose()} />

<div class="fixed inset-0 z-[70] flex items-end justify-center sm:items-center" transition:fade|global={{ duration: ms(200) }}>
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="vault-backdrop" class="absolute inset-0 cursor-default bg-black/60" onclick={onclose}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-labelledby="vault-prompt-title"
    use:modal={opener}
    transition:fly|global={{ y: 60, duration: ms(220) }}
    class="relative w-full max-w-sm rounded-t-3xl border border-line bg-surface p-6 sm:rounded-3xl"
  >
  <form onsubmit={submit}>
    <div class="flex items-center gap-3">
      <span class="text-muted"><Icon name="lock" size={20} /></span>
      <h2 id="vault-prompt-title" class="font-serif text-2xl">Senha mestra</h2>
    </div>
    <p class="mt-3 text-sm leading-relaxed text-muted">Digite a senha para decifrar <strong class="font-medium text-fg">{target}</strong> nesta sessão.</p>
    <input
      use:focusOnMount
      bind:value={password}
      oninput={() => (error = '')}
      type="password"
      autocomplete="current-password"
      aria-label="Senha mestra"
      aria-invalid={error ? 'true' : undefined}
      aria-describedby="vault-hint"
      maxlength="256"
      placeholder="••••••••"
      class="mt-4 h-12 w-full rounded-field border bg-bg px-4 {error ? 'border-offline' : 'border-field-line'}"
    />
    <p id="vault-hint" class="mt-2 font-mono text-xs {error ? 'text-offline-text' : 'text-muted'}" role={error ? 'alert' : undefined}>
      {error || 'nunca enviada ao servidor'}
    </p>
    <div class="mt-5 flex justify-end gap-3">
      <button type="button" class="h-11 rounded-field border border-field-line px-4 text-sm hover:bg-line/40" onclick={onclose}>Cancelar</button>
      <button type="submit" class="h-11 rounded-field bg-cream px-4 text-sm font-semibold text-on-cream hover:bg-cream/90">Desbloquear</button>
    </div>
  </form>
  </div>
</div>
