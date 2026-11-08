<script lang="ts">
  import type { Snippet } from 'svelte'
  import { TONES, type BlockType, type CalloutTone, type HeadingLevel } from '../../stores/blocks'
  import Icon from '../dashboard/Icon.svelte'
  import InsertMenu from './InsertMenu.svelte'

  interface Props {
    id: string
    label: string
    index: number
    count: number
    readOnly: boolean
    menuOpen: boolean
    /** Where a block being dragged would land relative to this one. */
    dropEdge: 'before' | 'after' | null
    onplus: () => void
    onpick: (type: BlockType, opts?: { level?: HeadingLevel; toggle?: boolean }) => void
    onclosemenu: () => void
    disabledTypes?: BlockType[]
    onmove: (delta: -1 | 1) => void
    onremove: () => void
    /** Plain text blocks can become one another; the menu then offers "Transformar em". */
    turnable?: boolean
    kind?: string
    canDuplicate?: boolean
    onduplicate?: () => void
    onturn?: (type: 'paragraph' | 'heading' | 'quote' | 'callout' | 'toggle' | 'bullet' | 'numbered', opts?: { level?: HeadingLevel; toggle?: boolean }) => void
    /** A heading's size, and a callout's tone: the menu offers the others. */
    level?: HeadingLevel
    /** The heading is also a toggle. */
    headingToggle?: boolean
    tone?: CalloutTone
    ontone?: (tone: CalloutTone) => void
    ondragstart: (e: DragEvent) => void
    ondragend: () => void
    ondragover: (e: DragEvent) => void
    ondrop: (e: DragEvent) => void
    /** Touch and pen cannot use the browser's drag and drop, so the handle runs its own gesture and reports it here. */
    onpointerdrag?: (phase: 'start' | 'move' | 'end' | 'cancel', clientY: number) => void
    /** True while this block is the one being dragged. */
    dragging?: boolean
    /** Plays the entrance animation (off when the row is drawn again after scrolling back to it). */
    enter?: boolean
    children: Snippet
  }

  let { id, label, index, count, readOnly, menuOpen, dropEdge, onplus, onpick, onclosemenu, disabledTypes = [], onmove, onremove, turnable = false, kind = '', canDuplicate = true, onduplicate, onturn, level = 2, headingToggle = false, tone = 'info', ontone, ondragstart, ondragend, ondragover, ondrop, onpointerdrag, dragging = false, enter = true, children }: Props = $props()

  let options = $state(false)
  // On narrow screens the controls take no side gutter: they appear under the block that was last touched.
  let active = $state(false)

  // The mouse drags natively; touch and pen drag by pointer events (a short movement starts it, so a plain tap still opens the menu).
  let pointerKind = $state<'mouse' | 'touch'>('mouse')
  let gesture: { pointerId: number; startY: number; started: boolean } | null = null
  let swallowClick = false
  const THRESHOLD = 6

  function pointerDown(e: PointerEvent) {
    pointerKind = e.pointerType === 'mouse' ? 'mouse' : 'touch'
    if (pointerKind === 'mouse' || !onpointerdrag) return
    gesture = { pointerId: e.pointerId, startY: e.clientY, started: false }
    ;(e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId)
  }

  function pointerMove(e: PointerEvent) {
    if (!gesture || e.pointerId !== gesture.pointerId) return
    if (!gesture.started) {
      if (Math.abs(e.clientY - gesture.startY) < THRESHOLD) return
      gesture.started = true
      options = false
      onpointerdrag?.('start', e.clientY)
    }
    e.preventDefault()
    onpointerdrag?.('move', e.clientY)
  }

  function pointerUp(e: PointerEvent, cancelled = false) {
    if (!gesture || e.pointerId !== gesture.pointerId) return
    const { started } = gesture
    gesture = null
    if (!started) return
    // the click that follows a drag must not open the menu
    swallowClick = true
    setTimeout(() => (swallowClick = false), 80)
    onpointerdrag?.(cancelled ? 'cancel' : 'end', e.clientY)
  }

  function handleClick() {
    if (swallowClick) return
    options = !options
  }

  const TURN: { type: 'paragraph' | 'heading' | 'quote' | 'callout' | 'toggle' | 'bullet' | 'numbered'; level?: HeadingLevel; toggle?: boolean; label: string }[] = [
    { type: 'paragraph', label: 'Texto' },
    { type: 'heading', level: 1, label: 'Título 1' },
    { type: 'heading', level: 2, label: 'Título 2' },
    { type: 'heading', level: 3, label: 'Título 3' },
    { type: 'bullet', label: 'Lista com marcadores' },
    { type: 'numbered', label: 'Lista numerada' },
    { type: 'quote', label: 'Citação' },
    { type: 'callout', label: 'Destaque' },
    { type: 'toggle', label: 'Toggle' },
    { type: 'heading', level: 1, toggle: true, label: 'Título 1 com toggle' },
    { type: 'heading', level: 2, toggle: true, label: 'Título 2 com toggle' },
    { type: 'heading', level: 3, toggle: true, label: 'Título 3 com toggle' },
  ]
  const isCurrent = (t: (typeof TURN)[number]) => t.type === kind && (t.type !== 'heading' || (t.level === level && !!t.toggle === headingToggle))

  function handleKey(e: KeyboardEvent) {
    if (e.altKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) {
      e.preventDefault()
      onmove(e.key === 'ArrowUp' ? -1 : 1)
    } else if (e.key === 'Escape') options = false
  }

  const reveal = 'transition-opacity group-focus-within/row:opacity-100 group-hover/row:opacity-100 focus-visible:opacity-100 max-md:opacity-100 [@media(hover:none)]:opacity-100'
</script>

<svelte:window
  onmousedown={(e) => options && !(e.target as Element).closest?.(`[data-options="${id}"]`) && (options = false)}
  onpointerdown={(e) => active && !(e.target as Element).closest?.(`[data-block-id="${id}"]`) && (active = false)}
/>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<div
  class="{enter ? 'animate-rise' : ''} group/row relative max-md:flex max-md:flex-col {dragging ? 'opacity-40' : ''} {menuOpen || options ? 'z-30' : ''} {dropEdge === 'before' ? 'shadow-[0_-2px_0_var(--color-accent-line)]' : ''} {dropEdge === 'after' ? 'shadow-[0_2px_0_var(--color-accent-line)]' : ''}"
  data-block-id={id}
  role="group"
  aria-label="{label} {index + 1} de {count}"
  style:animation-delay="{Math.min(index, 10) * 28}ms"
  {ondragover}
  {ondrop}
  onfocusin={() => (active = true)}
  onclick={() => (active = true)}
>
  {#if !readOnly}
    <div class="flex items-center gap-0.5 max-md:order-last max-md:justify-end max-md:pt-1 md:absolute md:top-1 md:-left-[4.25rem] {active || options || menuOpen ? '' : 'max-md:hidden'}">
      <button
        type="button"
        data-insert-trigger
        class="grid size-7 place-items-center rounded text-muted opacity-0 hover:bg-line/50 {reveal}"
        aria-label="Inserir bloco depois de {label} {index + 1}"
        aria-haspopup="menu"
        aria-expanded={menuOpen}
        onclick={onplus}
      >
        <Icon name="plus" size={16} />
      </button>
      <div class="relative" data-options={id}>
        <button
          type="button"
          draggable={pointerKind === 'mouse'}
          class="grid size-7 cursor-grab touch-none place-items-center rounded text-muted opacity-0 hover:bg-line/50 [@media(pointer:coarse)]:size-10 {reveal}"
          aria-label="Opções de {label} {index + 1}"
          aria-haspopup="menu"
          aria-expanded={options}
          title="Arrastar para reordenar (ou Alt + setas)"
          {ondragstart}
          {ondragend}
          onkeydown={handleKey}
          onpointerdown={pointerDown}
          onpointermove={pointerMove}
          onpointerup={(e) => pointerUp(e)}
          onpointercancel={(e) => pointerUp(e, true)}
          onclick={handleClick}
        >
          ⠿
        </button>
        {#if options}
          <div role="menu" aria-label="Opções do bloco" class="animate-pop absolute top-full left-0 max-md:right-0 max-md:left-auto z-40 mt-1 w-48 rounded-field border border-line bg-surface p-1 shadow-xl">
            <button type="button" role="menuitem" class="w-full rounded-[7px] px-2.5 py-1.5 text-left text-sm hover:bg-line/50 disabled:opacity-40" disabled={index === 0} onclick={() => ((options = false), onmove(-1))}>Subir</button>
            <button type="button" role="menuitem" class="w-full rounded-[7px] px-2.5 py-1.5 text-left text-sm hover:bg-line/50 disabled:opacity-40" disabled={index === count - 1} onclick={() => ((options = false), onmove(1))}>Descer</button>
            {#if canDuplicate}
              <button type="button" role="menuitem" class="w-full rounded-[7px] px-2.5 py-1.5 text-left text-sm hover:bg-line/50" onclick={() => ((options = false), onduplicate?.())}>Duplicar</button>
            {/if}
            {#if kind === 'callout'}
              <div class="my-1 border-t border-line pt-1 pl-2.5 font-mono text-[10px] tracking-[0.14em] text-muted uppercase" aria-hidden="true">Tom do destaque</div>
              <div class="flex gap-1 px-1.5 pb-1">
                {#each TONES as t (t.key)}
                  <button type="button" role="menuitemradio" aria-checked={tone === t.key} aria-label="Tom {t.label}" title={t.label} class="grid size-8 place-items-center rounded text-base hover:bg-line/50 {tone === t.key ? 'bg-line/60 ring-1 ring-accent-line' : ''}" onclick={() => ((options = false), ontone?.(t.key))}>{t.icon}</button>
                {/each}
              </div>
            {/if}
            {#if turnable}
              <div class="my-1 border-t border-line pt-1 pl-2.5 font-mono text-[10px] tracking-[0.14em] text-muted uppercase" aria-hidden="true">Transformar em</div>
              {#each TURN.filter((t) => !isCurrent(t)) as t (`${t.type}${t.level ?? ''}${t.toggle ? 't' : ''}`)}
                <button type="button" role="menuitem" class="w-full rounded-[7px] px-2.5 py-1.5 text-left text-sm hover:bg-line/50" onclick={() => ((options = false), onturn?.(t.type, t.level ? { level: t.level, toggle: t.toggle } : undefined))}>{t.label}</button>
              {/each}
              <div class="my-1 border-t border-line" aria-hidden="true"></div>
            {/if}
            <button type="button" role="menuitem" class="w-full rounded-[7px] px-2.5 py-1.5 text-left text-sm text-offline-text hover:bg-line/50" onclick={() => ((options = false), onremove())}>Excluir</button>
          </div>
        {/if}
      </div>
    </div>
  {/if}
  {@render children()}
  {#if menuOpen}<InsertMenu {onpick} onclose={onclosemenu} disabled={disabledTypes} />{/if}
</div>
