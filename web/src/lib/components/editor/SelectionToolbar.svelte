<script lang="ts">
  import { makeLink, safeUrl, toggleMark, type Mark } from '../../stores/inline'
  import { applyEdit } from './fieldEdit'

  interface Props {
    /** The field the selection is in. */
    field: HTMLTextAreaElement
    onerror: (message: string) => void
  }

  let { field, onerror }: Props = $props()

  let linking = $state(false)
  let url = $state('')
  let bar: HTMLElement | undefined = $state()

  // fixed above the block the selection is in; a textarea cannot say where its selection is drawn
  const rect = $derived((field.closest('[data-block-id]') ?? field).getBoundingClientRect())
  const top = $derived(Math.max(8, rect.top - 46))
  const left = $derived(Math.min(Math.max(8, rect.left), Math.max(8, window.innerWidth - 292)))

  function mark(m: Mark) {
    applyEdit(field, toggleMark(field.value, field.selectionStart, field.selectionEnd, m))
  }

  function link(e: SubmitEvent) {
    e.preventDefault()
    if (!safeUrl(url)) return onerror('Endereço inválido: use http, https ou e-mail')
    applyEdit(field, makeLink(field.value, field.selectionStart, field.selectionEnd, url))
    linking = false
    url = ''
  }

  const btn = 'grid h-8 min-w-8 place-items-center rounded px-2 text-sm hover:bg-line/60'
  // the field must keep its selection, so the bar never takes the focus on press
  const keep = (e: MouseEvent) => !(e.target as Element).closest('input') && e.preventDefault()
</script>

<div
  bind:this={bar}
  role="toolbar"
  aria-label="Formatar texto"
  tabindex="-1"
  class="animate-pop fixed z-40 flex items-center gap-0.5 rounded-field border border-line bg-surface p-1 shadow-xl"
  style:top="{top}px"
  style:left="{left}px"
  onmousedown={keep}
>
  {#if linking}
    <form class="flex items-center gap-1" onsubmit={link}>
      <input
        bind:value={url}
        aria-label="Endereço do link"
        placeholder="https://…"
        maxlength="2000"
        class="h-8 w-48 rounded border border-field-line bg-bg px-2 text-sm placeholder:text-muted"
        onkeydown={(e) => e.key === 'Escape' && (e.stopPropagation(), (linking = false))}
      />
      <button type="submit" class="{btn} bg-accent">OK</button>
    </form>
  {:else}
    <button type="button" class="{btn} font-bold" aria-label="Negrito" title="Negrito (Ctrl B)" onclick={() => mark('bold')}>B</button>
    <button type="button" class="{btn} italic" aria-label="Itálico" title="Itálico (Ctrl I)" onclick={() => mark('italic')}>I</button>
    <button type="button" class="{btn} underline" aria-label="Sublinhado" title="Sublinhado (Ctrl U)" onclick={() => mark('underline')}>U</button>
    <button type="button" class="{btn} font-mono" aria-label="Código" title="Código" onclick={() => mark('code')}>&lt;/&gt;</button>
    <button type="button" class="{btn}" aria-label="Link" title="Link" onclick={() => (linking = true)}>Link</button>
  {/if}
</div>
