<script lang="ts">
  import type { IconName } from '../dashboard/Icon.svelte'
  import Icon from '../dashboard/Icon.svelte'

  export interface MoreItem {
    label: string
    icon: IconName
    onclick: () => void
    danger?: boolean
  }

  interface Props {
    items: MoreItem[]
  }

  let { items }: Props = $props()

  let open = $state(false)
  let root: HTMLElement | undefined = $state()
</script>

<svelte:window
  onkeydown={(e) => e.key === 'Escape' && open && (open = false)}
  onmousedown={(e) => open && root && !root.contains(e.target as Node) && (open = false)}
/>

<div class="relative" bind:this={root}>
  <button
    type="button"
    class="grid size-10 place-items-center rounded-field text-muted hover:bg-line/40 hover:text-fg {open ? 'bg-line/40 text-fg' : ''}"
    aria-label="Mais ações"
    aria-haspopup="menu"
    aria-expanded={open}
    onclick={() => (open = !open)}
  >
    <span aria-hidden="true" class="text-xl leading-none">⋯</span>
  </button>
  {#if open}
    <div role="menu" aria-label="Mais ações" class="animate-pop absolute top-full right-0 z-40 mt-1 w-52 rounded-field border border-line bg-surface p-1 shadow-xl" style:transform-origin="top right">
      {#each items as item (item.label)}
        <button
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-3 rounded-[7px] px-2.5 py-2 text-left text-sm hover:bg-line/50 {item.danger ? 'text-offline-text' : ''}"
          onclick={() => ((open = false), item.onclick())}
        >
          <Icon name={item.icon} size={16} />{item.label}
        </button>
      {/each}
    </div>
  {/if}
</div>
