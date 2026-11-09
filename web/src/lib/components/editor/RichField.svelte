<script lang="ts" module>
  // told once per page load, not at every focus
  let warned = false
</script>

<script lang="ts">
  // The focused text block: the rich-text editor sits where the plain field used to, and every change
  // goes back to the page as text with markers, so nothing else about the block changes.
  import { onDestroy, onMount, tick } from 'svelte'
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { barLock, instances, loadEngine, type RichInstance } from './rich/engine'
  import { autoMark, parseRuns, plainText, serializeRuns, sliceRuns } from './rich/runs'
  import { MAX_TEXT, type HeadingLevel } from '../../stores/blocks'
  import { place } from './autosize'
  import { toast } from '../../stores/toast.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { text: string }>
    label: string
    className: string
    placeholder: string
    caret: 'start' | 'end'
    /** The block stopped being edited (focus left it). */
    onclose: () => void
    onsplit: (id: string) => void
    onremove: (id: string) => void
    onslash: (id: string) => void
    onenter?: () => void
  }

  let { ed, block, label, className, placeholder, caret, onclose, onsplit, onremove, onslash, onenter }: Props = $props()

  let host: HTMLElement | undefined = $state()
  let inst: RichInstance | null = null
  let empty = $state(false)
  let gone = false
  let native = $state(false)
  // the rich editor could not be loaded (no connection and not cached yet): the text is edited as plain text, markers shown
  let plain = $state(false)
  let area: HTMLTextAreaElement | undefined = $state()
  // an undo must not trigger the symbol shortcuts again, or `**x**` could never be undone
  let skipAuto = false

  onMount(() => {
    void start()
  })

  async function start() {
    let make
    try {
      make = await loadEngine()
    } catch {
      if (gone || !host) return
      await fallback()
      return
    }
    if (gone || !host) return
    inst = make(host, {
      runs: parseRuns(block.text),
      editable: ed.can('text'),
      label,
      className: 'outline-none',
      placeholder,
      maxLength: MAX_TEXT,
      onChange: changed,
      onSelection: () => document.dispatchEvent(new Event('selectionchange')),
      onBlur: blur,
    })
    instances.set(host, inst)
    native = inst.nativePlaceholder
    inst.focus()
    empty = plainText(inst.runs()) === ''
    const end = plainText(inst.runs()).length
    const at = caret === 'start' ? 0 : end
    inst.setSelection(at, at)
  }

  async function fallback() {
    plain = true
    if (!warned) {
      warned = true
      toast.show('Sem conexão: o editor completo não carregou. Você pode editar como texto simples.')
    }
    await tick()
    if (!area) return
    area.focus()
    const at = caret === 'start' ? 0 : area.value.length
    area.setSelectionRange(at, at)
  }

  function plainKey(e: KeyboardEvent) {
    if (!area || e.isComposing || !ed.can('text')) return
    if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
      e.preventDefault()
      e.stopPropagation()
      const made = ed.splitText(block.id, area.value.slice(0, area.selectionStart), area.value.slice(area.selectionEnd))
      if (made) onsplit(made.id)
    } else if (e.key === 'Backspace' && area.value === '' && (block.type === 'paragraph' || block.type === 'quote' || block.type === 'callout')) {
      e.preventDefault()
      e.stopPropagation()
      onremove(block.id)
    }
  }

  onDestroy(() => {
    gone = true
    if (host) instances.delete(host)
    inst?.destroy()
    inst = null
  })

  function changed() {
    if (!inst) return
    let runs = inst.runs()
    const text = plainText(runs)
    empty = text === ''
    // "# ", "- ", "1. ", "> " typed in an empty paragraph turn it into a title, a list item or a quote
    if (block.type === 'paragraph' && ed.can('blocks') && /^(#{1,3}|[-*+]|\d{1,3}[.)]|>) $/.test(text)) {
      const mark = text.trimEnd()
      const done = mark[0] === '#' ? ed.turnInto(block.id, 'heading', { level: mark.length as HeadingLevel }) : mark === '>' ? ed.turnInto(block.id, 'quote') : /\d/.test(mark[0]) ? ed.turnInto(block.id, 'numbered') : ed.turnInto(block.id, 'bullet')
      if (done) {
        ed.setText(block.id, '')
        // the block changed kind, so a new field takes over: the caret goes back into it
        onsplit(block.id)
        return
      }
    }
    if (text === '/' && block.type === 'paragraph' && ed.can('blocks')) {
      inst.replace(0, 1, [])
      ed.setText(block.id, '')
      onslash(block.id)
      return
    }
    const sel = inst.selection()
    if (!skipAuto && sel.from === sel.to) {
      const found = autoMark(text.slice(0, sel.from), text.slice(sel.to))
      if (found && sliceRuns(runs, found.from, found.to).every((r) => !Object.keys(r.marks).length)) {
        inst.replace(found.from, found.to, [{ text: found.inner, marks: { [found.mark]: true } }])
        runs = inst.runs()
      }
    }
    skipAuto = false
    ed.setText(block.id, serializeRuns(runs))
  }

  function blur(e: FocusEvent) {
    // the formatting bar keeps the block open while the person types a link address
    if (barLock.linking || (e.relatedTarget as Element | null)?.closest?.('[aria-label="Formatar texto"]')) return
    // taking the field out of the page fires a blur too: by then the block is already going away
    queueMicrotask(() => host?.isConnected && onclose())
  }

  function neighbour(prev: boolean) {
    const root = host?.closest('article') ?? document
    const navs = [...root.querySelectorAll<HTMLElement>('[data-nav]')]
    return navs[navs.indexOf(host!) + (prev ? -1 : 1)]
  }

  function keydown(e: KeyboardEvent) {
    if (!inst || e.isComposing) return
    const mod = e.ctrlKey || e.metaKey
    const k = e.key.toLowerCase()
    if (mod && !e.altKey) {
      if (k === 'z' || k === 'y') skipAuto = true
      const mark = e.shiftKey ? (k === 's' || k === 'x' ? 'strike' : k === 'h' ? 'highlight' : null) : k === 'b' ? 'bold' : k === 'i' ? 'italic' : k === 'u' ? 'underline' : null
      if (mark) {
        e.preventDefault()
        e.stopPropagation()
        if (ed.can('text')) inst.toggle(mark)
      }
      return
    }
    const sel = inst.selection()
    const runs = inst.runs()
    const len = plainText(runs).length
    const isItem = block.type === 'bullet' || block.type === 'numbered'
    if (e.key === 'Tab' && isItem && !e.altKey) {
      // a list item goes in one level (Tab) or out (Shift+Tab); outside a list Tab keeps moving through the page
      e.preventDefault()
      e.stopPropagation()
      if (ed.can('text')) ed.indent(block.id, e.shiftKey ? -1 : 1)
      return
    }
    if (e.key === 'Enter' && !e.altKey) {
      e.preventDefault()
      e.stopPropagation()
      if (!ed.can('text')) return
      // Enter on an empty list item ends the list (or comes out one level)
      if (isItem && len === 0 && !e.shiftKey) {
        if (ed.leaveList(block.id)) onsplit(block.id)
        return
      }
      if (e.shiftKey) return inst.replace(sel.from, sel.to, [{ text: '\n', marks: {} }])
      if ((block.type === 'toggle' || (block.type === 'heading' && block.toggle)) && onenter) return onenter()
      const made = ed.splitText(block.id, serializeRuns(sliceRuns(runs, 0, sel.from)), serializeRuns(sliceRuns(runs, sel.to, len)))
      if (made) onsplit(made.id)
    } else if (e.key === 'Backspace' && len === 0 && isItem && ed.can('text')) {
      // Backspace on an empty list item undoes the list the same way Enter does
      e.preventDefault()
      e.stopPropagation()
      if (ed.leaveList(block.id)) onsplit(block.id)
    } else if (e.key === 'Backspace' && len === 0 && (block.type === 'paragraph' || block.type === 'quote' || block.type === 'callout')) {
      e.preventDefault()
      e.stopPropagation()
      onremove(block.id)
    } else if (!e.shiftKey && !e.altKey && sel.from === sel.to && (e.key === 'ArrowUp' || e.key === 'ArrowDown' || e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
      const prev = e.key === 'ArrowUp' || e.key === 'ArrowLeft'
      if (prev ? sel.from !== 0 : sel.from !== len) return
      const target = neighbour(prev)
      if (!target) return
      e.preventDefault()
      e.stopPropagation()
      place(target, prev ? 'end' : 'start')
    }
  }
</script>

<!-- The engine builds its editable element inside this one, which wears the block's look so nothing moves when the
     field swaps in. Key presses are read on the way down so the page's rules win. -->
<div bind:this={host} class="relative [&_a]:text-accent-text [&_a]:underline [&_code]:rounded [&_code]:bg-line/60 [&_code]:px-1 [&_code]:font-mono [&_code]:text-[0.9em] [&_u]:underline-offset-4 [&_mark]:rounded-sm [&_mark]:bg-accent/45 [&_mark]:text-fg {className}" data-rich data-nav tabindex="-1" onfocus={() => inst?.focus()} onkeydowncapture={plain ? plainKey : keydown} role="presentation">
  {#if plain}
    <textarea
      bind:this={area}
      aria-label={label}
      {placeholder}
      value={block.text}
      readonly={!ed.can('text')}
      maxlength={MAX_TEXT}
      rows="1"
      data-nav
      data-plain
      class="block w-full resize-none overflow-hidden bg-transparent p-0 text-inherit outline-none [field-sizing:content] placeholder:text-muted/70"
      oninput={(e) => ed.setText(block.id, e.currentTarget.value)}
      onblur={blur}
    ></textarea>
  {/if}
  {#if empty && !native && !plain}
    <span class="pointer-events-none absolute text-muted/70" aria-hidden="true">{placeholder}</span>
  {/if}
</div>
