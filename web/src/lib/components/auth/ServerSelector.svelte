<script lang="ts">
  import { tick } from 'svelte'
  import { scale } from 'svelte/transition'
  import { ms } from '../../motion'
  import StatusDot from './StatusDot.svelte'
  import { directory, selection, type ServerOption } from '../../stores/servers.svelte'
  import { manual, type ManualServer } from '../../stores/manual.svelte'
  import { toast } from '../../stores/toast.svelte'

  interface Props {
    onadd?: () => void
  }

  let { onadd }: Props = $props()

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  let trigger: HTMLButtonElement | undefined = $state()
  let menu: HTMLDivElement | undefined = $state()

  /** What the arrow keys visit: every menu entry that can take the focus right now. */
  const entries = () =>
    menu ? [...menu.querySelectorAll<HTMLButtonElement>('button[role^="menuitem"]:not(:disabled)')] : []

  /**
   * A health check or a new server can rebuild the list under the person's finger, destroying the very entry that has
   * the focus (the browser then sends it to the page's start). Put it back on the entry at the same place.
   */
  function keepFocus(node: HTMLElement) {
    let at = 0
    const remember = () => {
      const i = entries().indexOf(document.activeElement as HTMLButtonElement)
      if (i >= 0) at = i
    }
    node.addEventListener('focusin', remember)
    const observer = new MutationObserver(() => {
      if (document.activeElement && document.activeElement !== document.body) return
      const list = entries()
      list[Math.min(at, list.length - 1)]?.focus()
    })
    observer.observe(node, { childList: true, subtree: true })
    return {
      destroy() {
        observer.disconnect()
        node.removeEventListener('focusin', remember)
      },
    }
  }

  function openMenu(at: 'first' | 'last' = 'first') {
    open = true
    // the menu exists only after this update; the first (or last) entry gets the focus so the arrows work at once
    void tick().then(() => {
      const list = entries()
      ;(at === 'last' ? list[list.length - 1] : (list.find((e) => e.getAttribute('aria-checked') === 'true') ?? list[0]))?.focus()
    })
  }

  function closeMenu(returnFocus = true) {
    if (!open) return
    open = false
    if (returnFocus) trigger?.focus()
  }

  function onmenukey(e: KeyboardEvent) {
    const list = entries()
    const at = list.indexOf(document.activeElement as HTMLButtonElement)
    let to: number | undefined
    switch (e.key) {
      case 'ArrowDown':
        to = at < 0 ? 0 : (at + 1) % list.length
        break
      case 'ArrowUp':
        to = at < 0 ? list.length - 1 : (at - 1 + list.length) % list.length
        break
      case 'Home':
        to = 0
        break
      case 'End':
        to = list.length - 1
        break
      case 'Tab':
        // a menu is one stop in the tab order: leaving it closes it
        closeMenu(false)
        return
      default:
        return
    }
    e.preventDefault()
    if (to !== undefined) list[to]?.focus()
  }

  function ontriggerkey(e: KeyboardEvent) {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      openMenu(e.key === 'ArrowUp' ? 'last' : 'first')
    }
  }

  // what the button shows; the spoken name must contain it (voice control says what it sees: "clicar Pindrel")
  const shown = $derived(selection.connecting ? `Abrindo ${selection.connecting.name}…` : selection.selected.name)
  const offline = $derived(selection.health === 'disconnected')
  // the page's server, when it does not respond, leaves "Disponíveis" and goes to "Desconectados"
  const available = $derived(offline ? directory.others : directory.list)

  const asOption = (m: ManualServer): ServerOption => ({
    id: m.id,
    name: m.name,
    address: m.address,
    url: m.url,
    serverId: m.serverId,
    manual: true,
    trustName: m.trustName,
  })
  // a server typed in is down when its own check says so, whatever the rest of the network does
  const addedUp = $derived(manual.list.filter((m) => manual.health[m.id] !== 'disconnected'))
  const addedDown = $derived(manual.list.filter((m) => manual.health[m.id] === 'disconnected'))
  const headings = $derived(offline || addedDown.length > 0)

  function forget(m: ManualServer) {
    manual.remove(m.id)
    toast.show(`${m.name} removido.`)
  }

  function choose(server: ServerOption) {
    closeMenu()
    void selection.open(server)
  }

  function add() {
    // the focus goes back to the button first: the dialog gives it back to the button when it closes
    closeMenu()
    onadd?.()
  }
</script>

{#snippet added(m: ManualServer, tone: 'online' | 'offline')}
  <div class="flex items-stretch gap-1" role="none" data-testid="added-server" data-tone={tone}>
    <button
      type="button"
      role="menuitemradio"
      aria-checked="false"
      disabled={!!selection.connecting}
      onclick={() => choose(asOption(m))}
      class="flex min-w-0 flex-1 items-center gap-2.5 rounded-lg border border-transparent px-2.5 py-2 text-left transition-colors duration-150 hover:bg-line/40 active:bg-line/70 {tone === 'offline' ? 'text-muted' : 'text-fg'}"
    >
      {#if manual.health[m.id]}<StatusDot {tone} fontSize={11} />{/if}
      <span class="min-w-0">
        <span class="block truncate text-sm font-semibold">{m.name}</span>
        <span class="block truncate font-mono text-[11px] tracking-[0.4px] text-muted">{m.address}</span>
      </span>
    </button>
    <button
      type="button"
      role="menuitem"
      aria-label="Remover {m.name}"
      onclick={() => forget(m)}
      class="shrink-0 rounded-lg px-2.5 text-muted transition-colors duration-150 hover:bg-line/40 hover:text-fg active:bg-line/70"
    >
      <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M18 6 6 18M6 6l12 12" />
      </svg>
    </button>
  </div>
{/snippet}

<svelte:window
  onclick={(e) => {
    if (open && root && !root.contains(e.target as Node)) open = false
  }}
  onkeydown={(e) => {
    if (e.key === 'Escape' && open) closeMenu()
  }}
/>

<div class="relative" bind:this={root}>
  <button
    type="button"
    aria-label="Selecionar servidor: {shown}"
    aria-haspopup="menu"
    aria-expanded={open}
    bind:this={trigger}
    onkeydown={ontriggerkey}
    onclick={() => (open ? closeMenu(false) : openMenu())}
    class="flex max-w-31 items-center gap-2.5 rounded-field border border-field-line bg-surface px-2.5 py-1.5 font-mono text-[11px] uppercase tracking-[1px] text-fg transition-colors duration-150 hover:bg-line/40 active:bg-line/70"
  >
    <StatusDot tone={offline ? 'offline' : 'online'} fontSize={11} testid="status-dot" />
    <span class="truncate">{shown}</span>
    <svg
      class="size-4 shrink-0 text-muted transition-transform duration-200 motion-reduce:transition-none {open ? 'rotate-180' : ''}"
      data-testid="chevron"
      viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path d="m6 9 6 6 6-6" />
    </svg>
  </button>

  {#if open}
    <div
      role="menu"
      aria-label="Servidores"
      tabindex="-1"
      bind:this={menu}
      use:keepFocus
      onkeydown={onmenukey}
      transition:scale|global={{ start: 0.92, duration: ms(200) }}
      class="absolute right-0 z-20 mt-2 min-w-60 origin-top-right rounded-field border border-line bg-surface p-1.5"
    >
      {#if headings}
        <p role="presentation" class="px-2.5 pt-3 pb-1 font-mono text-[10px] uppercase tracking-[1.4px] text-muted">Disponíveis</p>
      {/if}
      {#each available as server (server.id)}
        {@const active = server.id === selection.selected.id}
        <button
          type="button"
          role="menuitemradio"
          aria-checked={active}
          disabled={!!selection.connecting}
          data-selected={active}
          onclick={() => choose(server)}
          class="flex w-full items-center justify-between rounded-lg border px-2.5 py-2 text-left transition-colors duration-150 hover:bg-line/40 active:bg-line/70 {active
            ? 'border-accent-line bg-accent/45 text-accent-text'
            : 'border-transparent text-fg'}"
        >
          <span>
            <span class="block text-sm font-semibold">{server.name}</span>
            <span class="block font-mono text-[11px] tracking-[0.4px] text-muted">{server.id === selection.selected.id ? selection.shownAddress : server.address}</span>
          </span>
          {#if active}
            <svg class="size-[18px]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" data-testid="selected-check">
              <path d="M20 6 9 17l-5-5" />
            </svg>
          {/if}
        </button>
      {/each}
      {#if !directory.loaded}
        <div class="flex flex-col gap-2 px-2.5 py-2" data-testid="servers-skeleton" aria-hidden="true">
          {#each [0, 1] as row (row)}
            <div class="h-9 rounded-lg bg-line/60 motion-safe:animate-pulse"></div>
          {/each}
        </div>
      {:else if directory.others.length === 0}
        <p role="presentation" class="px-2.5 py-2 font-mono text-[11px] tracking-[0.4px] text-muted">Nenhum outro servidor na rede.</p>
      {/if}
      {#each addedUp as m (m.id)}
        {@render added(m, 'online')}
      {/each}
      {#if headings}
        <p role="presentation" class="px-2.5 pt-3 pb-1 font-mono text-[10px] uppercase tracking-[1.4px] text-muted">Desconectados</p>
      {/if}
      {#each addedDown as m (m.id)}
        {@render added(m, 'offline')}
      {/each}
      {#if offline}
        <div
          role="menuitemradio"
          aria-checked="true"
          data-selected="true"
          data-offline="true"
          class="flex w-full items-center justify-between rounded-lg border border-offline bg-offline/15 px-2.5 py-2 text-left"
        >
          <span>
            <span class="block text-sm font-semibold text-muted">{selection.selected.name}</span>
            <span class="block font-mono text-[11px] tracking-[0.4px] text-muted">{selection.shownAddress}</span>
          </span>
          <svg class="size-[18px] text-offline" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M20 6 9 17l-5-5" />
          </svg>
        </div>
      {/if}
      <div class="my-1 border-t border-line"></div>
      <button
        type="button"
        role="menuitem"
        onclick={add}
        class="w-full rounded-lg px-2.5 py-2 text-left font-mono text-xs tracking-[0.4px] text-muted transition-colors duration-150 hover:bg-line/40 active:bg-line/70"
      >
        + Adicionar servidor...
      </button>
    </div>
  {/if}
</div>
