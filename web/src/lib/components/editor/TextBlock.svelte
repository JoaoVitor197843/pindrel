<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { renderMarks } from '../../stores/inline'
  import { autosize } from './autosize'
  import { barLock, loadEngine } from './rich/engine'
  import RichField from './RichField.svelte'
  import { canObserve, nearView } from './nearView'
  import { tick } from 'svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'paragraph' | 'heading' | 'quote' | 'callout' | 'toggle' | 'spoiler' | 'secure' }>
    variant?: 'paragraph' | 'heading'
    /** The selection toolbar (bold, italic, underline, strike, code, link) works here. Off for secrets. */
    format?: boolean
    /** Called with Enter on a toggle's title, to move on to its body. */
    onenter?: () => void
    label: string
    /** Called when Enter split the block: the new block should get the focus. */
    onsplit: (id: string) => void
    /** Backspace in an empty paragraph: the page removes it and moves the caret to the block before. */
    onremove: (id: string) => void
    /** An empty block that got a "/" asks for the insert menu. */
    onslash: (id: string) => void
  }

  let { ed, block, variant = 'paragraph', format = true, onenter, label, onsplit, onremove, onslash }: Props = $props()

  // A block whose text has marks (**bold**, *italic*, __underline__, ~~strike~~, ==highlight==, `code`, [link](url)) is drawn formatted while nobody edits it and
  // becomes the plain field on focus, where the marks show. Blocks without marks (nearly all) are fields all the time.
  let editing = $state(false)
  // A text block is text until focused, and then the rich-text editor takes its place (no field at rest). Secrets stay plain fields.
  let caret = $state<'start' | 'end'>('end')
  let field: HTMLTextAreaElement | undefined = $state()
  // Far from the screen a block is drawn as text too: a field costs about ten times the memory of a <div>. Secrets stay fields.
  let near = $state(!canObserve())
  const marked = $derived(format && block.type !== 'secure' && !editing ? renderMarks(block.text) : null)
  const richOn = $derived(format && block.type !== 'secure')
  const asView = $derived(!editing && (richOn || marked !== null || (!near && block.type !== 'secure')))

  async function startEdit(e: FocusEvent) {
    // a page that cannot be edited (trash, read-only share) keeps the drawn text: nothing to open
    if (richOn && !ed.can('text')) return
    const where = (e.currentTarget as HTMLElement).dataset.caret === 'start' ? 'start' : 'end'
    caret = where
    if (richOn) {
      // the view stays on screen (and focused) while the engine downloads the first time
      const view = e.currentTarget as HTMLElement
      try {
        await loadEngine()
      } catch {
        return
      }
      if (document.activeElement !== view) return
      editing = true
      return
    }
    editing = true
    await tick()
    if (!field) return
    field.focus()
    const at = where === 'start' ? 0 : field.value.length
    field.setSelectionRange(at, at)
  }

  function viewDown(e: MouseEvent) {
    // pressing a link must follow it: focusing the block would swap it for the field before the click lands
    if ((e.target as Element).closest('a')) e.preventDefault()
  }

  function blur(e: FocusEvent) {
    // the formatting bar keeps the block open while the person types a link address
    if (!barLock.linking && !(e.relatedTarget as Element | null)?.closest?.('[aria-label="Formatar texto"]')) editing = false
  }

  const look = $derived(
    variant === 'heading'
      ? 'font-serif text-2xl leading-snug font-semibold'
      : block.type === 'quote'
        ? 'border-l-2 border-accent-line pl-4 font-serif text-lg leading-[1.6] text-fg/85 italic'
        : block.type === 'callout'
          ? 'rounded-field border border-line bg-surface py-3 pr-4 pl-12 text-[16px] leading-[1.6]'
          : block.type === 'toggle'
            ? 'text-[16.5px] leading-[1.68] font-medium'
            : 'text-[16.5px] leading-[1.68] text-fg/90',
  )

  function onkeydown(e: KeyboardEvent) {
    const el = e.currentTarget as HTMLTextAreaElement
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault()
      if (block.type === 'toggle' && onenter) return onenter()
      const made = ed.split(block.id, el.selectionStart)
      if (made) onsplit(made.id)
    } else if (e.key === 'Backspace' && el.value === '' && (block.type === 'paragraph' || block.type === 'quote' || block.type === 'callout')) {
      e.preventDefault()
      onremove(block.id)
    }
  }

  function oninput(e: Event & { currentTarget: HTMLTextAreaElement }) {
    const el = e.currentTarget
    if (el.value === '/' && block.type === 'paragraph' && ed.can('blocks')) {
      ed.setText(block.id, '')
      el.value = ''
      onslash(block.id)
      return
    }
    ed.setText(block.id, el.value)
  }
</script>

<div class="relative" use:nearView={(n) => (near = n)}>
{#if block.type === 'callout'}<span class="pointer-events-none absolute top-3 left-4 text-lg" aria-hidden="true">💡</span>{/if}
{#if asView}
  <div
    role="textbox"
    aria-readonly="true"
    aria-label={label}
    tabindex="0"
    data-nav
    data-view
    onfocus={startEdit}
    onmousedown={viewDown}
    class="block w-full cursor-text bg-transparent break-words whitespace-pre-wrap [&_a]:text-accent-text [&_a]:underline [&_u]:underline-offset-4 [&_mark]:rounded-sm [&_mark]:bg-accent/45 [&_mark]:text-fg [&_code]:rounded [&_code]:bg-line/60 [&_code]:px-1 [&_code]:font-mono [&_code]:text-[0.9em] {look}"
  >
    {#if marked !== null}{@html marked}{:else}{block.text || '\u200b'}{/if}
  </div>
{:else if richOn}
  <RichField
    {ed}
    {block}
    {label}
    className={look}
    placeholder={variant === 'heading' ? 'Título' : block.type === 'quote' ? 'Citação' : block.type === 'callout' ? 'Destaque' : block.type === 'toggle' ? 'Título do toggle' : ''}
    {caret}
    onclose={() => (editing = false)}
    {onsplit}
    {onremove}
    {onslash}
    {onenter}
  />
{:else}
  <textarea
    bind:this={field}
    data-nav
    data-fmt={format && block.type !== 'secure' ? '' : undefined}
    rows="1"
    value={block.text}
    {oninput}
    {onkeydown}
    onfocus={() => (editing = true)}
    onblur={blur}
    use:autosize={block.text}
    readonly={!ed.can('text')}
    spellcheck="false"
    maxlength="20000"
    aria-label={label}
    placeholder={variant === 'heading' ? 'Título' : block.type === 'quote' ? 'Citação' : block.type === 'callout' ? 'Destaque' : block.type === 'toggle' ? 'Título do toggle' : ''}
    class="block w-full resize-none overflow-hidden bg-transparent break-words placeholder:text-muted/70 {look}"
  ></textarea>
{/if}
</div>
