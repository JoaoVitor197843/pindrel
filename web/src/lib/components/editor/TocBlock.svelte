<script lang="ts">
  import { outline } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'

  interface Props {
    ed: PageEditor
    /** Scrolls to the section with this block id. */
    onjump: (blockId: string) => void
  }

  let { ed, onjump }: Props = $props()

  // nothing is stored: the list is read from the page's headings every time, so it can never be out of date
  const titles = $derived(outline(ed.blocks))
</script>

<nav aria-label="Sumário da página" class="rounded-field border border-line px-4 py-3">
  <p class="mb-1.5 font-mono text-[10px] tracking-[0.14em] text-muted uppercase">Sumário</p>
  {#if titles.length === 0}
    <p class="text-sm text-muted">Os títulos de seção aparecem aqui.</p>
  {:else}
    <ul class="flex flex-col">
      {#each titles as t (t.id)}
        <li style:padding-left="{(t.level - 1) * 1.1}rem">
          <button type="button" class="block w-full truncate rounded py-1 text-left text-sm text-fg/85 hover:text-accent-text hover:underline" onclick={() => onjump(t.id)}>{t.text}</button>
        </li>
      {/each}
    </ul>
  {/if}
</nav>
