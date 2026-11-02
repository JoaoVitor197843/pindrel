<script lang="ts">
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
    open = false
    void selection.open(server)
  }

  function add() {
    open = false
    onadd?.()
  }
</script>

{#snippet added(m: ManualServer, tone: 'online' | 'offline')}
  <div class="flex items-stretch gap-1" data-testid="added-server" data-tone={tone}>
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
    if (e.key === 'Escape') open = false
  }}
/>

<div class="relative" bind:this={root}>
  <button
    type="button"
    aria-label="Selecionar servidor"
    aria-haspopup="menu"
    aria-expanded={open}
    onclick={() => (open = !open)}
    class="flex max-w-31 items-center gap-2.5 rounded-field border border-line bg-surface px-2.5 py-1.5 font-mono text-[11px] uppercase tracking-[1px] text-fg transition-colors duration-150 hover:bg-line/40 active:bg-line/70"
  >
    <StatusDot tone={offline ? 'offline' : 'online'} fontSize={11} testid="status-dot" />
    <span class="truncate">{selection.connecting ? `Abrindo ${selection.connecting.name}…` : selection.selected.name}</span>
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
      transition:scale|global={{ start: 0.92, duration: ms(200) }}
      class="absolute right-0 z-20 mt-2 min-w-60 origin-top-right rounded-field border border-line bg-surface p-1.5"
    >
      {#if headings}
        <p class="px-2.5 pt-3 pb-1 font-mono text-[10px] uppercase tracking-[1.4px] text-muted">Disponíveis</p>
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
            ? 'border-accent-line bg-accent/45 text-accent-line'
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
        <p class="px-2.5 py-2 font-mono text-[11px] tracking-[0.4px] text-muted">Nenhum outro servidor na rede.</p>
      {/if}
      {#each addedUp as m (m.id)}
        {@render added(m, 'online')}
      {/each}
      {#if headings}
        <p class="px-2.5 pt-3 pb-1 font-mono text-[10px] uppercase tracking-[1.4px] text-muted">Desconectados</p>
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
