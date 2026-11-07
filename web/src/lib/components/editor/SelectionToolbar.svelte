<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte'
  import { makeLink, safeUrl, toggleMark, type Mark } from '../../stores/inline'
  import { applyEdit } from './fieldEdit'
  import { barLock, type RichInstance } from './rich/engine'

  interface Props {
    /** The field the selection is in (a plain field)... */
    field?: HTMLTextAreaElement
    /** ...or the rich-text engine of the block that has it, with the element that holds it. */
    rich?: { inst: RichInstance; el: HTMLElement }
    onerror: (message: string) => void
  }

  let { field, rich, onerror }: Props = $props()

  let linking = $state(false)
  let url = $state('')
  let input: HTMLInputElement | undefined = $state()
  let bar: HTMLElement | undefined = $state()
  // what was selected when the link field opened: the field takes the focus, and the selection must survive it
  let saved = { from: 0, to: 0 }

  // On a touch screen the system draws its own menu (cut, copy, paste) right above the selection, so the bar sits at the
  // bottom of what the person sees, above the keyboard, where nothing else is.
  const coarse = typeof matchMedia === 'function' && matchMedia('(pointer: coarse)').matches
  let seen = $state({ top: 0, height: typeof innerHeight === 'number' ? innerHeight : 0 })
  const syncSeen = () => {
    const v = window.visualViewport
    seen = { top: v?.offsetTop ?? 0, height: v?.height ?? window.innerHeight }
  }
  onMount(() => {
    if (!coarse) return
    syncSeen()
    window.visualViewport?.addEventListener('resize', syncSeen)
    window.visualViewport?.addEventListener('scroll', syncSeen)
    return () => {
      window.visualViewport?.removeEventListener('resize', syncSeen)
      window.visualViewport?.removeEventListener('scroll', syncSeen)
    }
  })
  onDestroy(() => {
    barLock.linking = false
  })

  // fixed above the block the selection is in; a textarea cannot say where its selection is drawn
  const anchor = $derived((field ?? rich!.el) as HTMLElement)
  const rect = $derived((anchor.closest('[data-block-id]') ?? anchor).getBoundingClientRect())
  const top = $derived(coarse ? Math.max(8, seen.top + seen.height - 56) : Math.max(8, rect.top - 46))
  const left = $derived(Math.min(Math.max(8, rect.left), Math.max(8, window.innerWidth - 292)))

  function mark(m: Mark) {
    if (rich) return rich.inst.toggle(m)
    if (field) applyEdit(field, toggleMark(field.value, field.selectionStart, field.selectionEnd, m))
  }

  async function startLink() {
    saved = rich ? rich.inst.selection() : { from: field!.selectionStart, to: field!.selectionEnd }
    barLock.linking = true
    linking = true
    await tick()
    input?.focus()
  }

  /** Back to the text with the same words selected, whether or not a link was made. */
  function finishLink() {
    linking = false
    url = ''
    barLock.linking = false
    if (rich) {
      rich.inst.focus()
      rich.inst.setSelection(saved.from, saved.to)
    } else if (field) {
      field.focus()
      field.setSelectionRange(saved.from, saved.to)
    }
  }

  function link(e: SubmitEvent) {
    e.preventDefault()
    const safe = safeUrl(url)
    if (!safe) return onerror('Endereço inválido: use http, https ou e-mail')
    if (rich) {
      rich.inst.setSelection(saved.from, saved.to)
      rich.inst.setLink(safe)
    } else if (field) {
      field.setSelectionRange(saved.from, saved.to)
      applyEdit(field, makeLink(field.value, saved.from, saved.to, url))
    }
    linking = false
    url = ''
    barLock.linking = false
  }

  function unlink() {
    if (rich) rich.inst.setLink(null)
  }

  const btn = 'grid h-9 min-w-9 place-items-center rounded px-2 text-sm hover:bg-line/60 md:h-8 md:min-w-8'
  // the field must keep its selection, so the bar never takes the focus on press
  const keep = (e: MouseEvent) => !(e.target as Element).closest('input') && e.preventDefault()
</script>

<div
  bind:this={bar}
  role="toolbar"
  aria-label="Formatar texto"
  tabindex="-1"
  class="animate-pop fixed z-40 flex items-center gap-0.5 rounded-field border border-line bg-surface p-1 shadow-xl {coarse ? 'justify-center' : ''}"
  style:top="{top}px"
  style:left="{coarse ? 8 : left}px"
  style:right={coarse ? '8px' : undefined}
  onmousedown={keep}
>
  {#if linking}
    <form class="flex w-full items-center gap-1" onsubmit={link}>
      <input
        bind:this={input}
        bind:value={url}
        aria-label="Endereço do link"
        placeholder="https://…"
        maxlength="2000"
        inputmode="url"
        autocapitalize="off"
        autocomplete="off"
        class="h-9 w-48 min-w-0 rounded border border-field-line bg-bg px-2 text-sm placeholder:text-muted {coarse ? 'flex-1' : ''} md:h-8"
        onkeydown={(e) => e.key === 'Escape' && (e.stopPropagation(), finishLink())}
      />
      <button type="submit" class="{btn} bg-accent">OK</button>
      <button type="button" class="{btn}" aria-label="Cancelar link" onclick={finishLink}>✕</button>
    </form>
  {:else}
    <button type="button" class="{btn} font-bold" aria-label="Negrito" title="Negrito (Ctrl B)" onclick={() => mark('bold')}>B</button>
    <button type="button" class="{btn} italic" aria-label="Itálico" title="Itálico (Ctrl I)" onclick={() => mark('italic')}>I</button>
    <button type="button" class="{btn} underline" aria-label="Sublinhado" title="Sublinhado (Ctrl U)" onclick={() => mark('underline')}>U</button>
    <button type="button" class="{btn} line-through" aria-label="Riscado" title="Riscado (Ctrl Shift S)" onclick={() => mark('strike')}>S</button>
    <button type="button" class="{btn}" aria-label="Marca-texto" title="Marca-texto (Ctrl Shift H)" onclick={() => mark('highlight')}><span class="rounded-sm bg-accent/45 px-1">A</span></button>
    <button type="button" class="{btn} font-mono" aria-label="Código" title="Código" onclick={() => mark('code')}>&lt;/&gt;</button>
    <button type="button" class="{btn}" aria-label="Link" title="Link" onclick={startLink}>Link</button>
    {#if rich}<button type="button" class="{btn}" aria-label="Tirar link" title="Tirar link" onclick={unlink}>⌀</button>{/if}
  {/if}
</div>
