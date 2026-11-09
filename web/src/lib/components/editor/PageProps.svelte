<script lang="ts">
  import { ago } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { formatDate } from '../../stores/workspace.svelte'
  import ShareBar from './ShareBar.svelte'
  import TagBar from './TagBar.svelte'

  interface Props {
    ed: PageEditor
    onshare: (tab: 'access' | 'add') => void
  }

  let { ed, onshare }: Props = $props()

  const page = $derived(ed.page)
  const noun = $derived(ed.blocks.length === 1 ? 'bloco' : 'blocos')
  const label = 'mb-1 font-mono text-[10.5px] tracking-[0.16em] text-muted uppercase'
</script>

{#if page}
  <dl class="grid grid-cols-2 gap-x-4 gap-y-4 text-sm" data-testid="meta" aria-label="Propriedades da página">
    <div class="col-span-2">
      <dt class={label}>Tags</dt>
      <dd class="min-w-0"><TagBar {ed} /></dd>
    </div>
    {#if !ed.ws.local}
      <div class="col-span-2">
        <dt class={label}>Pessoas</dt>
        <dd class="min-w-0"><ShareBar {ed} onopen={onshare} /></dd>
      </div>
    {/if}
    <div><dt class={label}>Dono</dt><dd>{page.sharedBy ?? ed.ws.ownerName}</dd></div>
    <div><dt class={label}>Criada</dt><dd>{formatDate(page.created)}</dd></div>
    <div class="col-span-2"><dt class={label}>Conteúdo</dt><dd>{ed.blocks.length} {noun}{#if ed.progress.total > 0}<span class="text-muted"> · </span>{ed.progress.done} de {ed.progress.total} feitas{/if}</dd></div>
    <div class="col-span-2"><dt class={label}>Editada</dt><dd>{ago(page.updated)}</dd></div>
  </dl>
{/if}
