<script lang="ts">
  import { LANGUAGES, type Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { highlight, type TokenKind } from './highlight'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'code' }>
  }

  let { ed, block }: Props = $props()

  const tokens = $derived(highlight(block.text, block.lang))
  const COLOR: Record<TokenKind, string> = {
    text: '',
    comment: 'text-muted italic',
    string: 'text-tag-teal',
    keyword: 'text-tag-rust',
    number: 'text-tag-gold',
  }

  function onkeydown(e: KeyboardEvent) {
    // Tab indents inside code instead of leaving the field; Escape hands the Tab key back
    if (e.key === 'Tab' && !e.shiftKey && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault()
      const el = e.currentTarget as HTMLTextAreaElement
      const { selectionStart: a, selectionEnd: b, value } = el
      ed.setText(block.id, `${value.slice(0, a)}    ${value.slice(b)}`)
      requestAnimationFrame(() => el.setSelectionRange(a + 4, a + 4))
    }
  }
</script>

<div class="overflow-hidden rounded-field border border-line bg-bg/60">
  <div class="flex items-center justify-between border-b border-line px-3 py-1.5">
    <select
      aria-label="Linguagem do código"
      disabled={!ed.can('text')}
      class="rounded bg-transparent font-mono text-[11px] tracking-[0.08em] text-muted uppercase"
      value={block.lang}
      onchange={(e) => ed.setLang(block.id, e.currentTarget.value)}
    >
      {#each LANGUAGES as lang (lang)}<option value={lang}>{lang}</option>{/each}
    </select>
  </div>
  <div class="relative">
    <!-- the colored copy sits under a transparent textarea: same font, same wrapping, so they line up -->
    <pre aria-hidden="true" class="pointer-events-none m-0 px-4 py-3 font-mono text-[13.5px] leading-[1.7] break-words whitespace-pre-wrap">{#each tokens as tok, i (i)}<span class={COLOR[tok.k]}>{tok.t}</span>{/each}{'\n'}</pre>
    <textarea
      data-nav
      value={block.text}
      oninput={(e) => ed.setText(block.id, e.currentTarget.value)}
      {onkeydown}
      readonly={!ed.can('text')}
      spellcheck="false"
      autocapitalize="off"
      maxlength="20000"
      aria-label="Código"
      placeholder="// novo bloco de código"
      class="absolute inset-0 block size-full resize-none overflow-hidden bg-transparent px-4 py-3 font-mono text-[13.5px] leading-[1.7] break-words whitespace-pre-wrap text-transparent caret-fg placeholder:text-muted/70"
    ></textarea>
  </div>
</div>
