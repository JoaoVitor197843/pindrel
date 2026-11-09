<script lang="ts">
  import { canVault } from '../../capabilities'
  import { onMount } from 'svelte'
  import type { BlockType, HeadingLevel } from '../../stores/blocks'

  interface Props {
    onpick: (type: BlockType, opts?: { level?: HeadingLevel; toggle?: boolean }) => void
    onclose: () => void
    /** Types the person may not create (for example images, without that permission). */
    disabled?: BlockType[]
  }

  let { onpick, onclose, disabled = [] }: Props = $props()

  const GROUPS: { label: string; items: { type: BlockType; level?: HeadingLevel; toggle?: boolean; label: string; glyph: string }[] }[] = [
    {
      label: 'Texto',
      items: [
        { type: 'paragraph', label: 'Texto', glyph: 'T' },
        { type: 'heading', level: 1, label: 'Título 1', glyph: 'H1' },
        { type: 'heading', level: 2, label: 'Título 2', glyph: 'H2' },
        { type: 'heading', level: 3, label: 'Título 3', glyph: 'H3' },
        { type: 'quote', label: 'Citação', glyph: '“' },
        { type: 'callout', label: 'Destaque', glyph: '!' },
      ],
    },
    {
      label: 'Listas e toggles',
      items: [
        { type: 'bullet', label: 'Lista com marcadores', glyph: '•' },
        { type: 'numbered', label: 'Lista numerada', glyph: '1.' },
        { type: 'checklist', label: 'Checklist', glyph: '✓' },
        { type: 'toggle', label: 'Toggle', glyph: '▸' },
        { type: 'heading', level: 1, toggle: true, label: 'Título 1 com toggle', glyph: '▸1' },
        { type: 'heading', level: 2, toggle: true, label: 'Título 2 com toggle', glyph: '▸2' },
        { type: 'heading', level: 3, toggle: true, label: 'Título 3 com toggle', glyph: '▸3' },
      ],
    },
    {
      label: 'Mídia e links',
      items: [
        { type: 'image', label: 'Imagem', glyph: '▣' },
        { type: 'video', label: 'Vídeo', glyph: '▶' },
        { type: 'audio', label: 'Áudio', glyph: '♪' },
        { type: 'file', label: 'Arquivo', glyph: '📎' },
        { type: 'pdf', label: 'PDF', glyph: 'PDF' },
        { type: 'bookmark', label: 'Link', glyph: '↗' },
        { type: 'pagelink', label: 'Link para página', glyph: '📄' },
      ],
    },
    {
      label: 'Dados e código',
      items: [
        { type: 'table', label: 'Tabela', glyph: '▦' },
        { type: 'code', label: 'Código', glyph: '</>' },
      ],
    },
    {
      label: 'Estrutura e sigilo',
      items: [
        { type: 'toc', label: 'Sumário', glyph: '☰' },
        { type: 'divider', label: 'Divisor', glyph: '—' },
        { type: 'spoiler', label: 'Spoiler', glyph: '◐' },
        ...(canVault() ? [{ type: 'secure' as const, label: 'Bloco seguro', glyph: '🔒' }] : []),
      ],
    },
  ]

  let menu: HTMLElement | undefined = $state()
  // always opens below its block (never over the items above it); when the screen has little room under it the menu
  // gets a shorter height and scrolls inside itself, and the page scrolls just enough to show all of it
  let maxHeight = $state<number | null>(null)
  const items = () => [...(menu?.querySelectorAll<HTMLElement>('[role="menuitem"]:not(:disabled)') ?? [])]

  onMount(() => {
    items()[0]?.focus({ preventScroll: true })
    if (!menu) return
    const top = menu.getBoundingClientRect().top
    const room = window.innerHeight - top - 12
    maxHeight = Math.max(160, Math.min(room, window.innerHeight * 0.55, 384))
    queueMicrotask(() => menu?.scrollIntoView?.({ block: 'nearest' }))
  })

  function onkeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault()
      e.stopPropagation()
      onclose()
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      const list = items()
      const i = list.indexOf(document.activeElement as HTMLElement)
      list[(i + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length]?.focus()
    }
  }
</script>

<svelte:window onmousedown={(e) => menu && !menu.contains(e.target as Node) && !(e.target as Element).closest?.('[data-insert-trigger]') && onclose()} />

<div
  bind:this={menu}
  role="menu"
  aria-label="Inserir bloco"
  tabindex="-1"
  class="animate-pop absolute left-0 z-40 max-h-[min(24rem,55dvh)] w-[min(14rem,calc(100vw-2rem))] overflow-x-hidden overflow-y-auto overscroll-contain rounded-field border border-line bg-surface p-1.5 shadow-xl [scrollbar-width:thin] top-full mt-2"
  style:max-height={maxHeight === null ? undefined : `${maxHeight}px`}
  {onkeydown}
>
  {#each GROUPS as group, g (group.label)}
    <div role="group" aria-label={group.label} class={g > 0 ? 'mt-1 border-t border-line pt-1' : ''}>
      <div class="px-2.5 pt-1.5 pb-1 font-mono text-[10px] tracking-[0.14em] text-muted uppercase" aria-hidden="true">{group.label}</div>
      {#each group.items as item (`${item.type}${item.level ?? ''}${item.toggle ? 't' : ''}`)}
        <button type="button" role="menuitem" disabled={disabled.includes(item.type)} class="flex w-full items-center gap-3 rounded-[7px] px-2.5 py-2 text-left text-sm hover:bg-line/50 focus-visible:bg-line/50 disabled:opacity-40" onclick={() => (item.level ? onpick(item.type, { level: item.level, toggle: item.toggle }) : onpick(item.type))}>
          <span class="grid size-6 shrink-0 place-items-center rounded border border-line font-mono text-[11px] text-muted" aria-hidden="true">{item.glyph}</span>
          {item.label}
        </button>
      {/each}
    </div>
  {/each}
</div>
