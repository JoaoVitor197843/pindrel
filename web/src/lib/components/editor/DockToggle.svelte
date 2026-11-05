<script lang="ts">
  import Icon from '../dashboard/Icon.svelte'

  interface Props {
    /** Which edge of the screen the panel belongs to. */
    side: 'left' | 'right'
    open: boolean
    label: string
    onclick: () => void
    /** "rail": the round arrow in the strip of a panel, in the middle of its height; "edge": a tab on the edge of the screen. */
    kind?: 'rail' | 'edge'
  }

  let { side, open, label, onclick, kind = 'rail' }: Props = $props()

  // the arrow points where the panel goes: toward the edge to close it, toward the page to open it
  const toward = $derived((side === 'left') === open ? 'chevron-left' : 'chevron-right')

  const look = $derived(
    kind === 'edge'
      ? `fixed top-1/2 z-30 h-16 w-8 -translate-y-1/2 border border-line bg-surface/90 text-muted backdrop-blur-sm hover:text-fg ${side === 'left' ? 'left-0 rounded-r-2xl border-l-0' : 'right-0 rounded-l-2xl border-r-0'}`
      : 'size-11 rounded-full border border-line bg-surface text-muted shadow-sm hover:text-fg',
  )
</script>

<button type="button" class="grid place-items-center {look}" aria-label={label} aria-expanded={open} data-side={side} {onclick}>
  <Icon name={toward} size={kind === 'edge' ? 20 : 22} />
</button>
