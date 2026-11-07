<script lang="ts">
  import type { PageEditor } from '../../stores/editor.svelte'
  import { ago } from '../../stores/blocks'
  import { formatDate } from '../../stores/workspace.svelte'
  import { prefs } from '../../stores/prefs.svelte'
  import Icon from '../dashboard/Icon.svelte'
  import { TAG_STYLE } from '../dashboard/tags'

  interface Props {
    ed: PageEditor
    /** Scrolls the page to a block. */
    onjump: (blockId: string) => void
    onopen?: (pageId: string) => void
    onduplicate: () => void
  }

  let { ed, onjump, onopen, onduplicate }: Props = $props()

  const page = $derived(ed.page)
  const stats = $derived(ed.stats)
  const items = $derived(ed.outline)
  const related = $derived(ed.related)
  const progress = $derived(ed.progress)
  const pct = $derived(progress.total ? Math.round((progress.done / progress.total) * 100) : 0)

  const heading = 'font-mono text-[10.5px] tracking-[0.16em] text-muted uppercase'
</script>

<aside aria-label="Painel da página" class="flex flex-col gap-7">
<p class="font-serif text-xl">Painel</p>

  <section aria-labelledby="panel-outline">
    <h2 id="panel-outline" class="mb-2">
      <button type="button" class="flex w-full items-center justify-between rounded py-0.5 text-left hover:text-fg {heading}" aria-expanded={!prefs.isFolded('outline')} onclick={() => prefs.toggleFold('outline')}>
        Nesta página<span aria-hidden="true" class="text-sm leading-none transition-transform {prefs.isFolded('outline') ? '' : 'rotate-90'}">›</span>
      </button>
    </h2>
    {#if !prefs.isFolded('outline')}
<div class="animate-rise">
    {#if items.length === 0}
      <p class="text-sm text-muted" data-testid="no-outline">Os títulos de seção aparecem aqui.</p>
    {:else}
      <ol class="flex flex-col border-l border-line">
        {#each items as item (item.id)}
          <li style:padding-left="{(item.level - 1) * 0.9}rem">
            <button type="button" class="-ml-px block w-full truncate border-l-2 border-transparent py-1.5 pl-3 text-left text-sm text-muted hover:border-accent-line hover:text-fg" onclick={() => onjump(item.id)}>
              {item.text}
            </button>
          </li>
        {/each}
      </ol>
    {/if}
</div>
    {/if}
  </section>

  <section aria-labelledby="panel-details">
    <h2 id="panel-details" class="mb-2">
      <button type="button" class="flex w-full items-center justify-between rounded py-0.5 text-left hover:text-fg {heading}" aria-expanded={!prefs.isFolded('details')} onclick={() => prefs.toggleFold('details')}>
        Detalhes<span aria-hidden="true" class="text-sm leading-none transition-transform {prefs.isFolded('details') ? '' : 'rotate-90'}">›</span>
      </button>
    </h2>
    {#if !prefs.isFolded('details')}
<div class="animate-rise">
    <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
      <div><dt class="font-mono text-xs text-muted">palavras</dt><dd data-testid="stat-words">{stats.words}</dd></div>
      <div><dt class="font-mono text-xs text-muted">leitura</dt><dd data-testid="stat-read">{stats.minutes ? `${stats.minutes} min` : '—'}</dd></div>
      <div><dt class="font-mono text-xs text-muted">blocos</dt><dd>{ed.blocks.length}</dd></div>
      <div><dt class="font-mono text-xs text-muted">caracteres</dt><dd>{stats.chars}</dd></div>
      <div><dt class="font-mono text-xs text-muted">criada</dt><dd>{page ? formatDate(page.created) : ''}</dd></div>
      <div><dt class="font-mono text-xs text-muted">editada</dt><dd>{page ? ago(page.updated) : ''}</dd></div>
    </dl>
    {#if progress.total > 0}
      <div class="mt-4">
        <div class="mb-1.5 flex items-center justify-between font-mono text-xs text-muted">
          <span>checklists</span><span>{progress.done} de {progress.total}</span>
        </div>
        <div role="progressbar" aria-label="Itens concluídos" aria-valuemin={0} aria-valuemax={progress.total} aria-valuenow={progress.done} class="h-1.5 overflow-hidden rounded-full bg-line">
          <div class="h-full rounded-full bg-accent-line transition-[width] duration-300" style="width: {pct}%"></div>
        </div>
      </div>
    {/if}
</div>
    {/if}
  </section>

  <section aria-labelledby="panel-related">
    <h2 id="panel-related" class="mb-2">
      <button type="button" class="flex w-full items-center justify-between rounded py-0.5 text-left hover:text-fg {heading}" aria-expanded={!prefs.isFolded('related')} onclick={() => prefs.toggleFold('related')}>
        Relacionadas<span aria-hidden="true" class="text-sm leading-none transition-transform {prefs.isFolded('related') ? '' : 'rotate-90'}">›</span>
      </button>
    </h2>
    {#if !prefs.isFolded('related')}
<div class="animate-rise">
    {#if related.length === 0}
      <p class="text-sm text-muted" data-testid="no-related">{page?.tags.length ? 'Nenhuma outra página com as mesmas tags.' : 'Adicione tags para ver páginas parecidas.'}</p>
    {:else}
      <ul class="flex flex-col gap-1">
        {#each related as other (other.id)}
          <li>
            <button type="button" class="w-full rounded-field px-2 py-1.5 text-left hover:bg-line/40 disabled:cursor-default" disabled={!onopen} onclick={() => onopen?.(other.id)}>
              <span class="block truncate font-serif text-[15px] font-semibold">{other.title}</span>
              <span class="mt-0.5 flex flex-wrap gap-x-2 font-mono text-[11px] text-muted">
                {#each other.tags.filter((t) => page?.tags.includes(t)) as id (id)}
                  {@const tag = ed.ws.tag(id)}
                  {#if tag}<span class="inline-flex items-center gap-1"><span class="size-1.5 rounded-full {TAG_STYLE[tag.color].dot}"></span>{tag.name}</span>{/if}
                {/each}
              </span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
</div>
    {/if}
  </section>

  <section aria-labelledby="panel-actions">
    <h2 id="panel-actions" class="mb-2">
      <button type="button" class="flex w-full items-center justify-between rounded py-0.5 text-left hover:text-fg {heading}" aria-expanded={!prefs.isFolded('actions')} onclick={() => prefs.toggleFold('actions')}>
        Ações<span aria-hidden="true" class="text-sm leading-none transition-transform {prefs.isFolded('actions') ? '' : 'rotate-90'}">›</span>
      </button>
    </h2>
    {#if !prefs.isFolded('actions')}
<div class="animate-rise">
    <div class="flex flex-col gap-2">
      {#if !ed.readOnly}
        <button type="button" class="inline-flex h-10 items-center gap-2 rounded-field border border-field-line px-3 text-sm hover:bg-line/40" aria-pressed={!!page?.pinned} onclick={() => ed.togglePin()}>
          <Icon name="pin" size={16} />{page?.pinned ? 'Desafixar página' : 'Fixar página'}
        </button>
      {/if}
      {#if ed.can('export') && !ed.readOnly}
        <button type="button" class="inline-flex h-10 items-center gap-2 rounded-field border border-field-line px-3 text-sm hover:bg-line/40" onclick={onduplicate}>
          <Icon name="copy" size={16} />Duplicar página
        </button>
      {/if}
    </div>
</div>
    {/if}
  </section>
</aside>
