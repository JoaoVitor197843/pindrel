<script lang="ts">
  import { MIN_VAULT_PASSWORD } from '../../stores/workspace.svelte'
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import Icon from '../dashboard/Icon.svelte'
  import TextBlock from './TextBlock.svelte'
  import { place } from './autosize'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'secure' }>
    onsplit: (id: string) => void
    onremove: (id: string) => void
    onslash: (id: string) => void
  }

  let { ed, block, onsplit, onremove, onslash }: Props = $props()

  let asking = $state(false)
  let password = $state('')
  let error = $state('')
  const open = $derived(!!ed.revealed[block.id])

  function view() {
    // the vault already open in this session needs no second password
    if (ed.ws.vaultUnlocked) ed.reveal(block.id, true)
    else asking = true
  }

  function submit(e: SubmitEvent) {
    e.preventDefault()
    if (ed.ws.unlockVault(password) !== 'ok') {
      error = `Senha incorreta — mínimo ${MIN_VAULT_PASSWORD} caracteres.`
      password = ''
      return
    }
    password = ''
    error = ''
    asking = false
    ed.reveal(block.id, true)
  }

  function cancel() {
    asking = false
    password = ''
    error = ''
  }

  function focusOnMount(node: HTMLInputElement) {
    place(node)
  }
</script>

<div class="flex items-start gap-3">
  <span class="mt-1 text-muted" title="Bloco seguro"><Icon name="lock" size={16} /><span class="sr-only">Bloco seguro</span></span>
  <div class="min-w-0 flex-1">
    {#if open}
      <div class="flex flex-col gap-1.5">
        <TextBlock {ed} {block} format={false} label="Texto do bloco seguro" {onsplit} {onremove} {onslash} />
        <button type="button" class="self-start font-mono text-[10px] tracking-[0.06em] text-offline-text underline" onclick={() => ed.reveal(block.id, false)}>
          ocultar novamente
        </button>
      </div>
    {:else if asking}
      <form class="flex flex-col gap-2.5 rounded-field border border-tag-gold/30 bg-surface px-4 py-4" onsubmit={submit}>
        <div class="font-mono text-[10.5px] tracking-[0.08em] text-tag-gold uppercase">senha do cofre</div>
        <div class="flex flex-wrap gap-2">
          <input
            use:focusOnMount
            bind:value={password}
            oninput={() => (error = '')}
            onkeydown={(e) => e.key === 'Escape' && (e.stopPropagation(), cancel())}
            type="password"
            autocomplete="current-password"
            maxlength="256"
            aria-label="Senha do cofre"
            aria-invalid={error ? 'true' : undefined}
            placeholder="••••••••"
            class="min-w-0 flex-1 basis-48 rounded-[7px] border bg-bg px-3 py-2.5 font-mono text-sm tracking-[0.14em] {error ? 'border-offline' : 'border-field-line'}"
          />
          <button type="submit" class="rounded-[7px] bg-accent px-4 py-2.5 text-xs font-medium hover:bg-accent/85">Desbloquear</button>
          <button type="button" class="rounded-[7px] border border-field-line px-4 py-2.5 text-xs text-muted hover:text-fg" onclick={cancel}>Cancelar</button>
        </div>
        <div class="font-mono text-xs {error ? 'text-offline-text' : 'text-muted'}" role={error ? 'alert' : undefined}>
          {error || 'a senha nunca é enviada ao servidor'}
        </div>
      </form>
    {:else if ed.can('secure')}
      <button type="button" class="rounded-[7px] border border-field-line px-5 py-2.5 text-xs font-medium hover:bg-line/40" aria-label="Ver bloco seguro" onclick={view}>Ver</button>
    {:else}
      <p class="font-mono text-xs text-muted">sem permissão para ver este bloco</p>
    {/if}
  </div>
</div>
