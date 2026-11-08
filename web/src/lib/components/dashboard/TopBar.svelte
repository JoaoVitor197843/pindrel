<script lang="ts">
  import Icon from './Icon.svelte'

  interface Props {
    query: string
    compact: boolean
    showMenuButton: boolean
    userName: string
    server: string
    onmenu: () => void
    onpalette: () => void
    onsettings: () => void
    onexport: () => void
    onlogout: () => void
    /** What the last entry of the account menu says: "Sair", or "Logar" while offline. */
    logoutLabel?: string
  }

  let { query = $bindable(), compact, showMenuButton, userName, server, onmenu, onpalette, onsettings, onexport, onlogout, logoutLabel = 'Sair' }: Props = $props()

  let userOpen = $state(false)
  let root: HTMLDivElement | undefined = $state()

  const initials = $derived(
    userName
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0]!.toUpperCase())
      .join('') || '?',
  )

  const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform || '')

  function pick(action: () => void) {
    userOpen = false
    action()
  }
</script>

<svelte:window
  onkeydown={(e) => e.key === 'Escape' && userOpen && (userOpen = false)}
  onmousedown={(e) => userOpen && root && !root.contains(e.target as Node) && (userOpen = false)}
/>

<header class="flex items-center gap-3 border-b border-line px-4 py-3 md:px-8">
  {#if showMenuButton}
    <button type="button" class="grid size-10 shrink-0 place-items-center rounded-field border border-field-line hover:bg-line/50" aria-label="Abrir menu" onclick={onmenu}>
      <Icon name="menu" />
    </button>
  {/if}

  <label class="relative min-w-0 flex-1 md:max-w-xl">
    <span class="sr-only">Buscar em todas as páginas</span>
    <span class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted"><Icon name="search" size={16} /></span>
    <input
      bind:value={query}
      type="search"
      maxlength="200"
      placeholder={compact ? 'Buscar…' : 'Buscar em todas as páginas…'}
      class="h-10 w-full rounded-field border border-field-line bg-surface pr-3 pl-9 text-sm placeholder:text-muted"
    />
  </label>
  <button
    type="button"
    class="inline-flex h-10 shrink-0 items-center gap-2 rounded-field border border-line px-3 font-mono text-xs text-muted hover:border-field-line hover:text-fg"
    aria-label="Abrir busca rápida"
    title="Busca rápida"
    onclick={onpalette}
  >
    <Icon name="search" size={14} />
    {#if !compact}<span>{isMac ? '⌘K' : 'Ctrl K'}</span>{/if}
  </button>

  <div class="relative ml-auto" bind:this={root}>
    <button
      type="button"
      class="flex h-11 items-center gap-3 rounded-field border border-transparent px-1 hover:bg-line/40 md:border-line md:px-2"
      aria-haspopup="menu"
      aria-expanded={userOpen}
      aria-label="Menu da conta de {userName}"
      onclick={() => (userOpen = !userOpen)}
    >
      <span class="grid size-9 place-items-center rounded-full bg-accent font-mono text-sm" aria-hidden="true">{initials}</span>
      {#if !compact}
        <span class="hidden text-left leading-tight lg:block">
          <span class="block text-sm font-medium">{userName}</span>
          <span class="block font-mono text-xs text-muted">{server}</span>
        </span>
      {/if}
      <span class="text-muted"><Icon name="chevron" size={16} /></span>
    </button>
    {#if userOpen}
      <div role="menu" aria-label="Conta" class="absolute right-0 z-30 mt-2 w-60 rounded-field border border-line bg-surface p-1 shadow-lg">
        <div class="px-3 py-2">
          <p class="text-sm font-medium">{userName}</p>
          <p class="font-mono text-xs text-muted">{server}</p>
        </div>
        <button type="button" role="menuitem" class="w-full rounded-field px-3 py-2 text-left text-sm hover:bg-line/50" onclick={() => pick(onsettings)}>Configurações</button>
        <button type="button" role="menuitem" class="w-full rounded-field px-3 py-2 text-left text-sm hover:bg-line/50" onclick={() => pick(onexport)}>Importar / exportar</button>
        <div class="my-1 border-t border-line"></div>
        <button type="button" role="menuitem" class="w-full rounded-field px-3 py-2 text-left text-sm hover:bg-line/50" onclick={() => pick(onlogout)}>{logoutLabel}</button>
      </div>
    {/if}
  </div>
</header>
