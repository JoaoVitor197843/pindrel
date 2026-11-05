<script lang="ts">
  import { onDestroy } from 'svelte'
  import { MAX_COLS, MAX_ROWS, MIN_COL_WIDTH, MAX_COL_WIDTH, type Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import Icon from '../dashboard/Icon.svelte'
  import { place } from './autosize'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'table' }>
  }

  let { ed, block }: Props = $props()

  let drag = $state<{ kind: 'col' | 'row'; i: number } | null>(null)
  let dropAt = $state<number | null>(null)
  let root: HTMLElement | undefined = $state()

  const width = $derived(block.cols.reduce((sum, c) => sum + c.w, 0) + 68)

  function over(e: DragEvent, kind: 'col' | 'row', i: number) {
    if (!drag || drag.kind !== kind) return
    e.preventDefault()
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    const after = kind === 'col' ? e.clientX > r.left + r.width / 2 : e.clientY > r.top + r.height / 2
    dropAt = i + (after ? 1 : 0)
  }

  function drop(e: DragEvent, kind: 'col' | 'row') {
    if (!drag || drag.kind !== kind || dropAt === null) return
    e.preventDefault()
    if (kind === 'col') ed.moveCol(block.id, drag.i, dropAt)
    else ed.moveRow(block.id, drag.i, dropAt)
    end()
  }

  function end() {
    drag = null
    dropAt = null
  }

  // Touch and pen cannot use the browser's drag and drop, so the grip runs its own gesture: a short movement starts it
  // (a plain tap does nothing), the finger picks the gap it is over and the table scrolls when it nears an edge.
  type Kind = 'col' | 'row'
  let pointerKind = $state<'mouse' | 'touch'>('mouse')
  let gesture: { id: number; kind: Kind; i: number; from: number; started: boolean } | null = null
  let finger = 0
  let frame: number | undefined

  const axisOf = (kind: Kind, e: PointerEvent) => (kind === 'col' ? e.clientX : e.clientY)

  function gapAt(kind: Kind, v: number): number {
    const items = [...(root?.querySelectorAll<HTMLElement>(kind === 'col' ? 'thead th[data-col]' : 'tbody tr') ?? [])]
    const at = items.findIndex((el) => {
      const r = el.getBoundingClientRect()
      return v < (kind === 'col' ? r.left + r.width / 2 : r.top + r.height / 2)
    })
    return at === -1 ? items.length : at
  }

  function follow() {
    if (!gesture?.started || !root) return
    const edge = 56
    if (gesture.kind === 'col') {
      const box = root.querySelector<HTMLElement>('.overflow-x-auto')
      const r = box?.getBoundingClientRect()
      if (box && r) {
        if (finger < r.left + edge) box.scrollLeft -= Math.ceil((r.left + edge - finger) / 4)
        else if (finger > r.right - edge) box.scrollLeft += Math.ceil((finger - (r.right - edge)) / 4)
      }
    } else {
      const page = root.closest('main')
      const r = page?.getBoundingClientRect()
      if (page && r) {
        if (finger < r.top + edge) page.scrollTop -= Math.ceil((r.top + edge - finger) / 4)
        else if (finger > r.bottom - edge) page.scrollTop += Math.ceil((finger - (r.bottom - edge)) / 4)
      }
    }
    dropAt = gapAt(gesture.kind, finger)
    frame = requestAnimationFrame(follow)
  }

  function gripDown(e: PointerEvent, kind: Kind, i: number) {
    pointerKind = e.pointerType === 'mouse' ? 'mouse' : 'touch'
    if (pointerKind === 'mouse' || !ed.can('tables')) return
    gesture = { id: e.pointerId, kind, i, from: axisOf(kind, e), started: false }
    ;(e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId)
  }

  function gripMove(e: PointerEvent) {
    if (!gesture || e.pointerId !== gesture.id) return
    const v = axisOf(gesture.kind, e)
    if (!gesture.started) {
      if (Math.abs(v - gesture.from) < 6) return
      gesture.started = true
      drag = { kind: gesture.kind, i: gesture.i }
      finger = v
      frame = requestAnimationFrame(follow)
    }
    e.preventDefault()
    finger = v
    dropAt = gapAt(gesture.kind, v)
  }

  function gripUp(e: PointerEvent, cancelled = false) {
    if (!gesture || e.pointerId !== gesture.id) return
    const g = gesture
    gesture = null
    if (frame !== undefined) cancelAnimationFrame(frame)
    frame = undefined
    if (g.started && !cancelled && dropAt !== null) {
      if (g.kind === 'col') ed.moveCol(block.id, g.i, dropAt)
      else ed.moveRow(block.id, g.i, dropAt)
    }
    end()
  }

  onDestroy(() => frame !== undefined && cancelAnimationFrame(frame))

  function start(e: DragEvent, kind: 'col' | 'row', i: number) {
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = 'move'
      e.dataTransfer.setData('text/plain', `${kind}:${i}`)
    }
    drag = { kind, i }
    dropAt = null
  }

  /** The grip also works from the keyboard: Alt + arrows moves the column or row. */
  function gripKey(e: KeyboardEvent, kind: 'col' | 'row', i: number) {
    if (!e.altKey) return
    const step = e.key === (kind === 'col' ? 'ArrowLeft' : 'ArrowUp') ? -1 : e.key === (kind === 'col' ? 'ArrowRight' : 'ArrowDown') ? 1 : 0
    if (!step) return
    e.preventDefault()
    const list = kind === 'col' ? block.cols.length : block.rows.length
    if (i + step < 0 || i + step >= list) return
    const at = step > 0 ? i + 2 : i - 1
    if (kind === 'col') ed.moveCol(block.id, i, at)
    else ed.moveRow(block.id, i, at)
  }

  function resizeStart(e: PointerEvent, colId: string, w: number) {
    e.preventDefault()
    const startX = e.clientX
    const move = (ev: PointerEvent) => ed.resizeCol(block.id, colId, w + ev.clientX - startX)
    const up = () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }

  function resizeKey(e: KeyboardEvent, colId: string, w: number) {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return
    e.preventDefault()
    ed.resizeCol(block.id, colId, w + (e.key === 'ArrowRight' ? 10 : -10))
  }

  /** Up/Down stay in the column; past the first/last row they leave the table for the field before/after it. */
  function cellKey(e: KeyboardEvent, row: number, col: number) {
    if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return
    if (e.shiftKey || e.altKey || e.ctrlKey || e.metaKey || !root) return
    const up = e.key === 'ArrowUp'
    let target: HTMLInputElement | HTMLTextAreaElement | null | undefined = root.querySelector<HTMLInputElement>(`[data-cell="${row + (up ? -1 : 1)}-${col}"]`)
    if (!target) {
      const outside = [...(root.closest('article') ?? document).querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('[data-nav]')].filter((n) => !root!.contains(n))
      target = up
        ? outside.filter((n) => root!.compareDocumentPosition(n) & Node.DOCUMENT_POSITION_PRECEDING).at(-1)
        : outside.find((n) => root!.compareDocumentPosition(n) & Node.DOCUMENT_POSITION_FOLLOWING)
    }
    // stopPropagation: the page-wide arrow handling must not also move the caret
    e.stopPropagation()
    if (target) {
      e.preventDefault()
      place(target, up ? 'end' : 'start')
    }
  }
</script>

<div bind:this={root} class="group/table" role="group" aria-label="Tabela">
  <div class="relative overflow-x-auto pb-2">
    <table class="table-fixed border-collapse text-sm" style="width: {width}px">
      <thead>
        <tr>
          <th class="w-8"><span class="sr-only">Mover linha</span></th>
          {#each block.cols as col, ci (col.id)}
            <th
              data-col
              class="relative border-b border-line p-0 text-left font-normal {drag?.kind === 'col' && drag.i === ci ? 'opacity-40' : ''} {drag?.kind === 'col' && dropAt === ci ? 'shadow-[inset_2px_0_0_var(--color-accent-line)]' : ''} {drag?.kind === 'col' && dropAt === ci + 1 && ci === block.cols.length - 1 ? 'shadow-[inset_-2px_0_0_var(--color-accent-line)]' : ''}"
              style="width: {col.w}px"
              ondragover={(e) => over(e, 'col', ci)}
              ondrop={(e) => drop(e, 'col')}
            >
              <div class="flex items-center gap-1 px-1 py-1.5">
                <button
                  type="button"
                  draggable={ed.can('tables') && pointerKind === 'mouse'}
                  disabled={!ed.can('tables')}
                  class="grid size-6 shrink-0 cursor-grab touch-none place-items-center rounded text-muted opacity-0 [@media(pointer:coarse)]:size-9 group-focus-within/table:opacity-100 group-hover/table:opacity-100 hover:bg-line/50 focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
                  aria-label="Mover coluna {col.label}"
                  title="Arrastar coluna (ou Alt + setas)"
                  ondragstart={(e) => start(e, 'col', ci)}
                  ondragend={end}
                  onpointerdown={(e) => gripDown(e, 'col', ci)}
                  onpointermove={gripMove}
                  onpointerup={(e) => gripUp(e)}
                  onpointercancel={(e) => gripUp(e, true)}
                  onkeydown={(e) => gripKey(e, 'col', ci)}
                >
                  ⠿
                </button>
                <input
                  data-nav
                  value={col.label}
                  oninput={(e) => ed.setLabel(block.id, col.id, e.currentTarget.value)}
                  readonly={!ed.can('text')}
                  maxlength="80"
                  aria-label="Nome da coluna {ci + 1}"
                  class="min-w-0 flex-1 bg-transparent font-mono text-[11px] tracking-[0.08em] text-muted uppercase"
                />
                {#if block.cols.length > 1 && ed.can('tables')}
                  <button
                    type="button"
                    class="grid size-6 shrink-0 place-items-center rounded text-muted opacity-0 group-focus-within/table:opacity-100 group-hover/table:opacity-100 hover:bg-line/50 focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
                    aria-label="Remover coluna {col.label}"
                    onclick={() => ed.removeCol(block.id, col.id)}
                  >
                    <Icon name="close" size={12} />
                  </button>
                {/if}
              </div>
              {#if ed.can('tables')}
                <!-- a focusable separator is a "splitter" widget: arrows resize it (ARIA authoring practice) -->
                <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
                <div
                  role="separator"
                  tabindex="0"
                  aria-orientation="vertical"
                  aria-label="Largura da coluna {col.label}"
                  aria-valuenow={col.w}
                  aria-valuemin={MIN_COL_WIDTH}
                  aria-valuemax={MAX_COL_WIDTH}
                  class="absolute inset-y-0 right-0 w-2 cursor-col-resize touch-none hover:bg-accent-line/40 focus-visible:bg-accent-line/40"
                  onpointerdown={(e) => resizeStart(e, col.id, col.w)}
                  onkeydown={(e) => resizeKey(e, col.id, col.w)}
                ></div>
              {/if}
            </th>
          {/each}
          <th class="w-9 border-b border-line p-0">
            <span class="sr-only">Adicionar coluna</span>
            {#if ed.can('tables') && block.cols.length < MAX_COLS}
              <button type="button" class="grid size-8 place-items-center rounded text-muted hover:bg-line/50" aria-label="Adicionar coluna" onclick={() => ed.addCol(block.id)}>
                <Icon name="plus" size={14} />
              </button>
            {/if}
          </th>
        </tr>
      </thead>
      <tbody>
        {#each block.rows as row, ri (ri)}
          <tr
            class="{drag?.kind === 'row' && drag.i === ri ? 'opacity-40' : ''} {drag?.kind === 'row' && dropAt === ri ? 'shadow-[inset_0_2px_0_var(--color-accent-line)]' : ''} {drag?.kind === 'row' && dropAt === ri + 1 && ri === block.rows.length - 1 ? 'shadow-[inset_0_-2px_0_var(--color-accent-line)]' : ''}"
            ondragover={(e) => over(e, 'row', ri)}
            ondrop={(e) => drop(e, 'row')}
          >
            <td class="p-0">
              <button
                type="button"
                draggable={ed.can('tables') && pointerKind === 'mouse'}
                disabled={!ed.can('tables')}
                class="grid size-6 cursor-grab touch-none place-items-center rounded text-muted opacity-0 [@media(pointer:coarse)]:size-9 group-focus-within/table:opacity-100 group-hover/table:opacity-100 hover:bg-line/50 focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
                aria-label="Mover linha {ri + 1}"
                title="Arrastar linha (ou Alt + setas)"
                ondragstart={(e) => start(e, 'row', ri)}
                ondragend={end}
                onpointerdown={(e) => gripDown(e, 'row', ri)}
                onpointermove={gripMove}
                onpointerup={(e) => gripUp(e)}
                onpointercancel={(e) => gripUp(e, true)}
                onkeydown={(e) => gripKey(e, 'row', ri)}
              >
                ⠿
              </button>
            </td>
            {#each block.cols as col, ci (col.id)}
              <td class="border-b border-line p-0">
                <input
                  data-nav
                  data-cell="{ri}-{ci}"
                  value={row[col.id] ?? ''}
                  oninput={(e) => ed.setCell(block.id, ri, col.id, e.currentTarget.value)}
                  onkeydown={(e) => cellKey(e, ri, ci)}
                  readonly={!ed.can('text')}
                  maxlength="2000"
                  aria-label="{col.label}, linha {ri + 1}"
                  class="w-full bg-transparent px-2 py-2 text-[15px]"
                />
              </td>
            {/each}
            <td class="p-0">
              {#if block.rows.length > 1 && ed.can('tables')}
                <button
                  type="button"
                  class="grid size-6 place-items-center rounded text-muted opacity-0 group-focus-within/table:opacity-100 group-hover/table:opacity-100 hover:bg-line/50 focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
                  aria-label="Remover linha {ri + 1}"
                  onclick={() => ed.removeRow(block.id, ri)}
                >
                  <Icon name="close" size={12} />
                </button>
              {/if}
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
  {#if ed.can('tables') && block.rows.length < MAX_ROWS}
    <button type="button" class="mt-1 rounded px-2 py-1 font-mono text-xs text-muted hover:bg-line/50 hover:text-fg" aria-label="Adicionar linha" onclick={() => ed.addRow(block.id)}>+ linha</button>
  {/if}
</div>
