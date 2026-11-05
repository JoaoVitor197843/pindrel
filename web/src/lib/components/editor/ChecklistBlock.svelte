<script lang="ts">
  import { tick } from 'svelte'
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { autosize, place } from './autosize'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'checklist' }>
    /** The last item is gone (or the list was left): the page removes/exits the block. */
    onremove: (id: string) => void
    onexit: (id: string) => void
  }

  let { ed, block, onremove, onexit }: Props = $props()
  let root: HTMLElement | undefined = $state()

  async function focusItem(itemId: string, where: 'start' | 'end' = 'end') {
    await tick()
    place(root?.querySelector<HTMLTextAreaElement>(`[data-item="${itemId}"]`), where)
  }

  function onkeydown(e: KeyboardEvent, itemId: string, index: number) {
    const el = e.currentTarget as HTMLTextAreaElement
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault()
      // Enter on an empty item ends the list: the item goes away and the caret moves on
      if (el.value === '' && block.items.length > 1) {
        ed.removeItem(block.id, itemId)
        onexit(block.id)
        return
      }
      const id = ed.addItem(block.id, itemId)
      if (id) void focusItem(id)
    } else if (e.key === 'Backspace' && el.value === '') {
      e.preventDefault()
      const before = block.items[index - 1]
      if (block.items.length <= 1) return onremove(block.id)
      const next = block.items[index + 1]
      ed.removeItem(block.id, itemId)
      if (before) void focusItem(before.id)
      else if (next) void focusItem(next.id, 'start')
    }
  }
</script>

<ul bind:this={root} class="flex flex-col gap-1.5" aria-label="Checklist">
  {#each block.items as item, i (item.id)}
    <li class="flex items-start gap-3">
      <button
        type="button"
        role="checkbox"
        aria-checked={item.done}
        aria-label="Marcar item {item.text || i + 1}"
        disabled={!ed.can('checklist')}
        class="mt-[5px] grid size-5 shrink-0 place-items-center rounded-[5px] border text-[13px] leading-none {item.done ? 'border-accent-line bg-accent text-fg' : 'border-field-line'}"
        onclick={() => ed.toggleItem(block.id, item.id)}
      >
        {item.done ? '✓' : ''}
      </button>
      <textarea
        data-nav
        data-item={item.id}
        rows="1"
        value={item.text}
        oninput={(e) => ed.setItemText(block.id, item.id, e.currentTarget.value)}
        onkeydown={(e) => onkeydown(e, item.id, i)}
        use:autosize={item.text}
        readonly={!ed.can('text')}
        spellcheck="false"
        maxlength="20000"
        aria-label="Item {i + 1}"
        placeholder="Novo item"
        class="block w-full resize-none overflow-hidden bg-transparent text-[16.5px] leading-[1.68] break-words placeholder:text-muted/70 {item.done ? 'text-muted line-through' : 'text-fg/90'}"
      ></textarea>
    </li>
  {/each}
</ul>
