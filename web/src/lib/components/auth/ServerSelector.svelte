<script lang="ts">
  import { directory, selection, type ServerOption } from '../../stores/servers.svelte'

  interface Props {
    onadd?: () => void
  }

  let { onadd }: Props = $props()

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()

  function choose(server: ServerOption) {
    open = false
    void selection.open(server)
  }

  function add() {
    open = false
    onadd?.()
  }
</script>

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
    class="flex max-w-31 items-center gap-2.5 rounded-field border border-line bg-surface px-2.5 py-1.5 font-mono text-[11px] uppercase tracking-[1px] text-fg"
  >
    <span class="relative size-2 shrink-0" data-testid="status-dot">
      <span class="absolute inset-0 rounded-full bg-accent-line opacity-60 motion-safe:animate-ping"></span>
      <span class="relative block size-full rounded-full bg-accent-line"></span>
    </span>
    <span class="truncate">{selection.connecting ? `Abrindo ${selection.connecting.name}…` : selection.selected.name}</span>
    <svg class="size-4 shrink-0 text-muted" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path d="m6 9 6 6 6-6" />
    </svg>
  </button>

  {#if open}
    <div
      role="menu"
      class="absolute right-0 z-20 mt-2 min-w-60 rounded-field border border-line bg-surface p-1.5"
    >
      {#each directory.list as server (server.id)}
        {@const active = server.id === selection.selected.id}
        <button
          type="button"
          role="menuitemradio"
          aria-checked={active}
          disabled={!!selection.connecting}
          data-selected={active}
          onclick={() => choose(server)}
          class="flex w-full items-center justify-between rounded-lg border px-2.5 py-2 text-left {active
            ? 'border-accent-line bg-accent/45 text-accent-line'
            : 'border-transparent text-fg'}"
        >
          <span>
            <span class="block text-sm font-semibold">{server.name}</span>
            <span class="block font-mono text-[11px] tracking-[0.4px] text-muted">{server.address}</span>
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
      <div class="my-1 border-t border-line"></div>
      <button
        type="button"
        role="menuitem"
        onclick={add}
        class="w-full rounded-lg px-2.5 py-2 text-left font-mono text-xs tracking-[0.4px] text-muted"
      >
        + Adicionar servidor...
      </button>
    </div>
  {/if}
</div>
