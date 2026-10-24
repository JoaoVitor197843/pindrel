<script lang="ts">
  interface Props {
    /** `online` (green) or `offline` (red). */
    tone: 'online' | 'offline'
    /** Size of a letter of the text beside it: 80% of the font size, rounded (as in the app). */
    fontSize: number
    testid?: string
  }

  let { tone, fontSize, testid }: Props = $props()

  const color = $derived(tone === 'online' ? 'bg-accent-line' : 'bg-offline')
  const size = $derived(Math.round(fontSize * 0.8))
</script>

<!-- The ring grows beyond the dot without taking up space; with "reduce motion" it stands still. -->
<span class="relative shrink-0" style="width: {size}px; height: {size}px" data-testid={testid} data-tone={tone}>
  <span class="absolute inset-0 rounded-full {color} motion-safe:animate-pulse-ring"></span>
  <span class="relative block size-full rounded-full {color}"></span>
</span>
