<script lang="ts" module>
  /** Height of each item the last time it was drawn, so an item that left the screen keeps its place in the list. */
  const heights = new Map<string, number>()
  export const forgetHeights = () => heights.clear()
</script>

<script lang="ts">
  import type { Snippet } from 'svelte'
  import { canObserve, nearView } from '../editor/nearView'

  interface Props {
    id: string
    /** Height to hold until the item has been drawn once. */
    estimate: number
    /** Drawn from the start, without waiting to learn that it is near the screen (the first screenful). */
    eager?: boolean
    /** Set on the empty box as `data-block-id`, for what looks blocks up by it (scrolling to one, finding the gap under a finger). */
    blockId?: string
    /** Gets whether this is the first time the item is drawn, so an entrance animation does not replay while scrolling. */
    children: Snippet<[boolean]>
  }

  let { id, estimate, eager = false, blockId, children }: Props = $props()

  // Far from the screen an item is an empty box of its last height: a card is about 70 DOM nodes and 75 KB of the
  // browser's memory, so a page list of a thousand would cost ~75 MB if every card were kept. Without
  // IntersectionObserver (old browsers, tests) every item is drawn.
  // Only `near` is reactive: the rest is read while drawing, which `near` itself triggers. Fewer reactive fields per
  // item is the point: a page can have thousands of them.
  // svelte-ignore state_referenced_locally
  let near = $state(eager || !canObserve())
  let box: HTMLElement | undefined
  // svelte-ignore non_reactive_update
  let firstDraw = true
  // svelte-ignore state_referenced_locally, non_reactive_update
  let height = heights.get(id) ?? estimate

  function report(isNear: boolean) {
    if (!isNear && near && box) {
      const h = box.getBoundingClientRect().height
      if (h > 0) {
        heights.set(id, h)
        height = h
      }
    }
    if (!isNear && near) firstDraw = false
    near = isNear
  }
</script>

<div bind:this={box} use:nearView={report} class="flex min-w-0 flex-col [&>*]:flex-1" style:min-height={near ? undefined : `${height}px`} data-lazy={near ? 'drawn' : 'empty'} data-block-id={near ? undefined : blockId} aria-hidden={near ? undefined : 'true'}>
  {#if near}{@render children(firstDraw)}{/if}
</div>
