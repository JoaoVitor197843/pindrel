<script lang="ts">
  import { fold } from '../../stores/workspace.svelte'

  interface Props {
    text: string
    query: string
  }

  let { text, query }: Props = $props()

  /** Pieces of `text`, the ones matching `query` (ignoring case and accents) flagged. */
  const parts = $derived.by(() => {
    const q = fold(query.trim())
    const folded = fold(text)
    // folding that changes the length (decomposed accents) would shift every position: show the text as it is
    if (!q || folded.length !== text.length) return [{ t: text, hit: false }]
    const out: { t: string; hit: boolean }[] = []
    let at = 0
    for (let i = folded.indexOf(q); i !== -1; i = folded.indexOf(q, at)) {
      if (i > at) out.push({ t: text.slice(at, i), hit: false })
      out.push({ t: text.slice(i, i + q.length), hit: true })
      at = i + q.length
    }
    if (at < text.length) out.push({ t: text.slice(at), hit: false })
    return out
  })
</script>

{#each parts as part}{#if part.hit}<mark class="rounded-sm bg-accent-line/30 text-fg">{part.t}</mark>{:else}{part.t}{/if}{/each}
