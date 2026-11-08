<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import TextBlock from './TextBlock.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'spoiler' }>
    onsplit: (id: string) => void
    onremove: (id: string) => void
    onslash: (id: string) => void
  }

  let { ed, block, onsplit, onremove, onslash }: Props = $props()
  const open = $derived(!!ed.revealed[block.id])
</script>

{#if open}
  <div class="flex flex-col gap-2">
    <div class="flex items-center gap-2 font-mono text-[10px] tracking-[0.1em] text-muted uppercase select-none">
      spoiler revelado
      <button type="button" class="underline hover:text-fg" onclick={() => ed.reveal(block.id, false)}>ocultar</button>
    </div>
    <TextBlock {ed} {block} label="Texto do spoiler" {onsplit} {onremove} {onslash} />
  </div>
{:else}
  <!-- the hidden text is not in the page at all, so it cannot be found, selected or read by mistake -->
  <button
    type="button"
    class="flex w-full items-center gap-3 rounded-field border border-dashed border-field-line bg-[repeating-linear-gradient(135deg,var(--color-surface)_0_8px,var(--color-bg)_8px_16px)] px-5 py-5 text-left select-none"
    aria-label="Revelar spoiler"
    onclick={() => ed.reveal(block.id, true)}
  >
    <span class="font-mono text-xs tracking-[0.06em] text-muted">Clique para revelar</span>
    <span class="font-mono text-[10.5px] tracking-[0.08em] text-muted uppercase">spoiler</span>
  </button>
{/if}
