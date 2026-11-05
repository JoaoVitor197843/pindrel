<script lang="ts">
  import { formatDate, type NotePage } from '../../stores/workspace.svelte'
  import Icon from './Icon.svelte'

  interface Props {
    pages: NotePage[]
    unlocked: boolean
    onlock: () => void
    /** Asks for the master password; `target` says what for (the vault, a new entry). */
    onunlock: (target: string) => void
    /** A row was chosen: the page opens (the password comes first when the vault is locked). */
    onopen: (page: NotePage) => void
    onadd: () => void
  }

  let { pages, unlocked, onlock, onunlock, onopen, onadd }: Props = $props()
</script>

<section aria-labelledby="vault-title">
  <div class="flex flex-wrap items-start justify-between gap-4">
    <div>
      <div class="flex flex-wrap items-center gap-3">
        <span class="text-muted"><Icon name={unlocked ? 'unlock' : 'lock'} size={22} /></span>
        <h1 id="vault-title" class="font-serif text-4xl font-bold">Cofre</h1>
        <span class="rounded-full bg-accent-line/15 px-2.5 py-1 font-mono text-[11px] tracking-[0.14em] text-accent-text">{unlocked ? 'DESBLOQUEADO' : 'BLOQUEADO'}</span>
      </div>
      <p class="mt-2 font-mono text-xs text-muted">Criptografado localmente — o servidor nunca vê o conteúdo.</p>
    </div>
    <div class="flex gap-2">
      {#if unlocked}
        <button type="button" class="h-11 rounded-field border border-field-line px-4 text-sm hover:bg-line/40" onclick={onlock}>Bloquear</button>
        <button type="button" class="inline-flex h-11 items-center gap-2 rounded-field bg-accent px-4 text-sm hover:bg-accent/85" onclick={onadd}>
          <Icon name="plus" size={16} />Nova entrada segura
        </button>
      {:else}
        <button type="button" class="inline-flex h-11 items-center gap-2 rounded-field bg-cream px-4 text-sm font-medium text-on-cream hover:bg-cream/90" onclick={() => onunlock('o cofre')}>
          <Icon name="unlock" size={16} />Desbloquear
        </button>
        <button type="button" class="inline-flex h-11 items-center gap-2 rounded-field bg-accent px-4 text-sm hover:bg-accent/85" onclick={() => onunlock('uma nova entrada')}>
          <Icon name="plus" size={16} />Nova entrada segura
        </button>
      {/if}
    </div>
  </div>

  {#if pages.length === 0}
    <div class="mt-8 flex flex-col items-center gap-2 rounded-field border border-dashed border-line p-10 text-center" data-testid="vault-empty">
      <span class="text-muted"><Icon name="lock" size={28} /></span>
      <h2 class="font-serif text-2xl">Nenhuma entrada no cofre ainda</h2>
      <p class="max-w-md text-sm text-muted">O conteúdo é cifrado neste dispositivo com a sua senha mestra antes de sair daqui.</p>
    </div>
  {:else}
    <ul class="mt-6 divide-y divide-line overflow-hidden rounded-field border border-line bg-surface">
      {#each pages as page (page.id)}
        <li>
          <button
            type="button"
            class="flex w-full items-center gap-4 px-4 py-3.5 text-left hover:bg-line/30"
            aria-label={unlocked ? undefined : `${page.title} (bloqueado)`}
            onclick={() => onopen(page)}
          >
            <span class="text-muted"><Icon name={unlocked ? 'unlock' : 'lock'} size={16} /></span>
            <span class="min-w-0 flex-1">
              <span class="block truncate font-serif text-base font-semibold">{page.title}</span>
              <span class="block truncate text-sm text-muted {unlocked ? '' : 'font-mono tracking-widest'}">
                {unlocked ? page.excerpt || 'sem conteúdo ainda' : '••••• ••••••••• ••••••'}
              </span>
            </span>
            <span class="hidden font-mono text-xs text-muted sm:block">{formatDate(page.updated)}</span>
            <span class="text-muted"><Icon name="chevron-right" size={16} /></span>
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</section>
