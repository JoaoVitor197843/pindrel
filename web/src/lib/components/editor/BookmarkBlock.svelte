<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { toast } from '../../stores/toast.svelte'
  import UrlForm from './UrlForm.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'bookmark' }>
  }

  let { ed, block }: Props = $props()

  // the card shows the title (or the site) and the address; nothing is fetched from the address
  let editing = $state(false)
  const host = $derived.by(() => {
    try {
      return new URL(block.url).hostname.replace(/^www\./, '')
    } catch {
      return block.url
    }
  })
</script>

{#if (block.url === '' || editing) && ed.can('text')}
  <UrlForm url={block.url} title={block.title} onsave={(u, t) => ed.setUrl(block.id, u, t) && ((editing = false), true)} onerror={(m) => toast.show(m)} />
{:else if block.url}
  <div class="flex items-center gap-3 rounded-field border border-line px-4 py-3 hover:bg-line/30">
    <a href={block.url} target="_blank" rel="noopener noreferrer" class="min-w-0 flex-1" aria-label="Abrir {block.title || host}">
      <span class="block truncate text-[15px] font-medium">{block.title || host}</span>
      <span class="block truncate font-mono text-xs text-muted">{block.url}</span>
    </a>
    {#if ed.can('text')}
      <button type="button" class="shrink-0 rounded px-2 py-1 text-sm text-muted hover:bg-line/50 hover:text-fg" onclick={() => (editing = true)}>Editar</button>
    {/if}
  </div>
{:else}
  <p class="rounded-field border border-line px-4 py-3 text-sm text-muted">Link sem endereço</p>
{/if}
