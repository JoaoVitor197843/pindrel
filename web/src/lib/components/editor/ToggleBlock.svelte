<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { autosize, place } from './autosize'
  import TextBlock from './TextBlock.svelte'

  interface Props {
    ed: PageEditor
    /** A toggle, or a heading that is also a toggle. */
    block: Extract<Block, { type: 'toggle' | 'heading' }>
    onsplit: (id: string) => void
    onremove: (id: string) => void
    onslash: (id: string) => void
  }

  let { ed, block, onsplit, onremove, onslash }: Props = $props()

  // open state lives with the page being edited, like spoilers: it closes with the page
  const open = $derived(!!ed.revealed[block.id])
  let body: HTMLTextAreaElement | undefined = $state()

  function toggle() {
    ed.reveal(block.id, !open)
  }

  function enter() {
    ed.reveal(block.id, true)
    queueMicrotask(() => place(body, 'start'))
  }
</script>

<div class="flex items-start gap-1">
  <button
    type="button"
    class="mt-1 grid size-7 shrink-0 place-items-center rounded text-muted hover:bg-line/50 hover:text-fg"
    aria-label={open ? 'Fechar toggle' : 'Abrir toggle'}
    aria-expanded={open}
    onclick={toggle}
  >
    <span aria-hidden="true" class="inline-block transition-transform motion-reduce:transition-none {open ? 'rotate-90' : ''}">▸</span>
  </button>
  <div class="min-w-0 flex-1">
    <TextBlock {ed} {block} variant={block.type === 'heading' ? 'heading' : 'paragraph'} label={block.type === 'heading' ? 'Título de seção' : 'Título do toggle'} {onsplit} {onremove} {onslash} onenter={enter} />
    {#if open}
      <textarea
        bind:this={body}
        data-nav
        data-fmt
        rows="1"
        value={block.body ?? ''}
        oninput={(e) => ed.setBody(block.id, e.currentTarget.value)}
        use:autosize={block.body ?? ''}
        readonly={!ed.can('text')}
        spellcheck="false"
        maxlength="20000"
        aria-label="Conteúdo do toggle"
        placeholder="Conteúdo escondido"
        class="animate-rise mt-1 block w-full resize-none overflow-hidden border-l border-line bg-transparent pl-4 text-[16px] leading-[1.65] text-fg/85 placeholder:text-muted/70"
      ></textarea>
    {/if}
  </div>
</div>
