<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { toast } from '../../stores/toast.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'pagelink' }>
    /** Goes to the page. */
    onopen?: (id: string) => void
  }

  let { ed, block, onopen }: Props = $props()

  const target = $derived(block.pageId ? ed.ws.page(block.pageId) : undefined)
  // a page in a vault that is still locked has no name to show
  const hidden = $derived(!!target && target.locked && !ed.ws.vaultUnlocked)
  let query = $state('')
  let changing = $state(false)

  // keep the remembered name in step with the page (it goes into exports)
  $effect(() => {
    if (block.pageId && ed.can('text')) ed.syncPageLink(block.id)
  })

  const MAX_RESULTS = 8
  const fold = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
  // never the whole workspace: a page list can have thousands of pages, and only a few are drawn
  const results = $derived.by(() => {
    const q = fold(query.trim())
    const out = []
    for (const p of ed.ws.pages) {
      if (p.id === ed.id || p.trashed || p.locked) continue
      if (q && !fold(p.title).includes(q)) continue
      out.push(p)
      if (out.length >= MAX_RESULTS) break
    }
    return out
  })

  function choose(id: string) {
    if (ed.setPageLink(block.id, id)) {
      changing = false
      query = ''
    } else toast.show('Não foi possível ligar a esta página')
  }
</script>

{#if (!block.pageId || changing) && ed.can('text')}
  <div class="rounded-field border border-line p-3">
    <input bind:value={query} aria-label="Buscar página para ligar" placeholder="Buscar uma página…" maxlength="120" autocomplete="off" class="mb-2 h-9 w-full rounded border border-field-line bg-bg px-2 text-sm placeholder:text-muted" />
    {#if results.length === 0}
      <p class="px-1 text-sm text-muted">Nenhuma página encontrada.</p>
    {:else}
      <ul class="flex flex-col">
        {#each results as p (p.id)}
          <li>
            <button type="button" class="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-line/50" aria-label="Ligar à página {p.title || 'Sem título'}" onclick={() => choose(p.id)}>
              <span aria-hidden="true">{p.icon || '📄'}</span>
              <span class="truncate">{p.title || 'Sem título'}</span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
    {#if changing}<button type="button" class="mt-2 rounded px-2 py-1 text-sm text-muted hover:bg-line/50" onclick={() => (changing = false)}>Cancelar</button>{/if}
  </div>
{:else if !block.pageId}
  <p class="rounded-field border border-line px-4 py-3 text-sm text-muted">Link para página sem destino</p>
{:else}
  <div class="flex items-center gap-3 rounded-field border border-line px-4 py-3 {target && !target.trashed && !hidden ? 'hover:bg-line/30' : ''}">
    {#if target && !target.trashed && !hidden}
      <button type="button" class="flex min-w-0 flex-1 items-center gap-2 text-left" aria-label="Abrir a página {target.title || 'Sem título'}" onclick={() => onopen?.(target.id)}>
        <span aria-hidden="true">{target.icon || '📄'}</span>
        <span class="truncate text-[15px] font-medium underline-offset-4 hover:underline">{target.title || 'Sem título'}</span>
      </button>
    {:else}
      <p class="min-w-0 flex-1 truncate text-[15px] text-muted">
        <span aria-hidden="true">📄 </span>{hidden ? 'Página do cofre' : (block.title || 'Página')}
        <span class="font-mono text-xs"> — {!target ? 'página não encontrada' : target.trashed ? 'na lixeira' : 'cofre bloqueado'}</span>
      </p>
    {/if}
    {#if ed.can('text')}
      <button type="button" class="shrink-0 rounded px-2 py-1 text-sm text-muted hover:bg-line/50 hover:text-fg" onclick={() => (changing = true)}>Trocar</button>
    {/if}
  </div>
{/if}
