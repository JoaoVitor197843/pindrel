<script lang="ts">
  interface Props {
    /** `online` (verde) ou `offline` (vermelho). */
    tone: 'online' | 'offline'
    /** Tamanho de uma letra do texto ao lado: 80% do corpo, arredondado (como no app). */
    fontSize: number
    testid?: string
  }

  let { tone, fontSize, testid }: Props = $props()

  const color = $derived(tone === 'online' ? 'bg-accent-line' : 'bg-offline')
  const size = $derived(Math.round(fontSize * 0.8))
</script>

<!-- O anel cresce além da bolinha sem ocupar espaço; com "reduzir movimento" ela fica parada. -->
<span class="relative shrink-0" style="width: {size}px; height: {size}px" data-testid={testid} data-tone={tone}>
  <span class="absolute inset-0 rounded-full {color} motion-safe:animate-pulse-ring"></span>
  <span class="relative block size-full rounded-full {color}"></span>
</span>
