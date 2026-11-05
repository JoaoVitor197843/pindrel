<script lang="ts">
  import { fade, scale } from 'svelte/transition'
  import { modal } from '../../a11y/dialog'
  import { ms } from '../../motion'
  import type { Workspace } from '../../stores/workspace.svelte'
  import Icon from './Icon.svelte'
  import { buildPalette, type PaletteActions } from './palette'
  import { TAG_STYLE } from './tags'

  interface Props {
    ws: Workspace
    actions: PaletteActions
    onclose: () => void
  }

  let { ws, actions, onclose }: Props = $props()

  const opener = document.activeElement
  let query = $state('')
  let index = $state(0)

  const groups = $derived(buildPalette(ws, query, actions))
  const flat = $derived(groups.flatMap((g) => g.items))
  const current = $derived(Math.min(index, Math.max(flat.length - 1, 0)))

  function onkeydown(e: KeyboardEvent) {
    if (!flat.length) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      index = (current + 1) % flat.length
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      index = (current - 1 + flat.length) % flat.length
    } else if (e.key === 'Enter') {
      e.preventDefault()
      flat[current]?.run()
    }
  }

  function focusOnMount(node: HTMLElement) {
    node.focus()
  }

  function scrollIntoView(node: HTMLElement, active: boolean) {
    if (active) node.scrollIntoView?.({ block: 'nearest' })
    return { update: (now: boolean) => now && node.scrollIntoView?.({ block: 'nearest' }) }
  }
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && onclose()} />

<div class="fixed inset-0 z-[70] flex items-start justify-center px-4 pt-[12vh]" transition:fade|global={{ duration: ms(150) }}>
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="palette-backdrop" class="absolute inset-0 cursor-default bg-black/60" onclick={onclose}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-label="Busca rápida"
    use:modal={opener}
    transition:scale|global={{ start: 0.97, duration: ms(150) }}
    class="relative flex max-h-[70vh] w-full max-w-xl flex-col overflow-hidden rounded-field border border-line bg-surface shadow-2xl"
  >
    <div class="flex items-center gap-3 border-b border-line px-4">
      <span class="text-muted"><Icon name="search" size={16} /></span>
      <input
        use:focusOnMount
        bind:value={query}
        oninput={() => (index = 0)}
        {onkeydown}
        role="combobox"
        aria-expanded="true"
        aria-controls="palette-list"
        aria-activedescendant={flat.length ? `pal-${current}` : undefined}
        aria-label="Buscar páginas, tags ou ações"
        maxlength="200"
        placeholder="Buscar páginas, tags ou ações…"
        class="h-12 min-w-0 flex-1 bg-transparent text-sm placeholder:text-muted focus:outline-none"
      />
      <kbd class="rounded border border-line px-1.5 py-0.5 font-mono text-[10px] text-muted">esc</kbd>
    </div>

    <div id="palette-list" role="listbox" aria-label="Resultados" class="min-h-0 flex-1 overflow-y-auto py-2">
      {#each groups as group (group.label)}
        <div role="group" aria-label={group.label}>
          <div class="px-4 pt-2 pb-1 font-mono text-[10px] tracking-[0.18em] text-muted uppercase" aria-hidden="true">{group.label}</div>
          {#each group.items as item (item.label)}
            {@const i = flat.indexOf(item)}
            {@const on = i === current}
            {@const tag = item.dot ? ws.tag(item.dot) : undefined}
            <div
              id="pal-{i}"
              role="option"
              tabindex="-1"
              aria-selected={on}
              use:scrollIntoView={on}
              class="flex cursor-pointer items-center gap-3 border-l-2 px-4 py-2.5 text-sm {on ? 'border-accent-line bg-line/50' : 'border-transparent'}"
              onmouseenter={() => (index = i)}
              onclick={item.run}
              onkeydown={(e) => e.key === 'Enter' && item.run()}
            >
              {#if tag}
                <span class="size-2.5 shrink-0 rounded-full {TAG_STYLE[tag.color].dot}"></span>
              {:else if item.icon}
                <span class="text-muted"><Icon name={item.icon} size={16} /></span>
              {/if}
              <span class="min-w-0 flex-1 truncate">{item.label}</span>
              <span class="shrink-0 font-mono text-xs text-muted">{item.meta}</span>
            </div>
          {/each}
        </div>
      {/each}
      {#if flat.length === 0}
        <div class="px-4 py-8 text-center">
          <p class="text-sm">Nada encontrado</p>
          <p class="font-mono text-xs text-muted">tente outro termo</p>
        </div>
      {/if}
    </div>

    <div class="flex items-center gap-4 border-t border-line px-4 py-2 font-mono text-[11px] text-muted">
      <span>↑↓ navegar</span><span>↵ abrir</span><span>esc fechar</span>
      <span class="ml-auto" role="status">{flat.length} {flat.length === 1 ? 'resultado' : 'resultados'}</span>
    </div>
  </div>
</div>
