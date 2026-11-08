<script lang="ts">
  import Highlight from './Highlight.svelte'
  import Icon from './Icon.svelte'
  import { TAG_STYLE } from './tags'
  import { formatDate, pageMeta, type Layout, type NotePage, type Tag } from '../../stores/workspace.svelte'

  interface Props {
    page: NotePage
    tags: Tag[]
    layout?: Layout
    query?: string
    trashed?: boolean
    ontrash?: () => void
    onrestore?: () => void
    onpin?: () => void
    /** Whether the vault is open: a vault page shows its text only then. */
    vaultUnlocked?: boolean
    /** Opens the page in the editor; without it the title is plain text. */
    onopen?: () => void
  }

  let { page, tags, layout = 'grid', query = '', trashed = false, ontrash, onrestore, onpin, onopen, vaultUnlocked = false }: Props = $props()

  const list = $derived(layout === 'list')
  const hidden = $derived(page.locked && !vaultUnlocked)
  const excerpt = $derived(hidden ? 'Conteúdo protegido. Desbloqueie o Cofre para visualizar esta página.' : page.excerpt || 'Página vazia. Comece a escrever.')
  const reveal =
    'transition-opacity group-focus-within:opacity-100 group-hover:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:opacity-100'
</script>

{#snippet title()}
  {#if onopen}
    <button type="button" data-icon={page.icon || undefined} class="text-left wrap-anywhere after:absolute after:inset-0 after:content-[''] {page.icon ? 'before:mr-1.5 before:content-[attr(data-icon)]' : ''}" onclick={onopen}><Highlight text={page.title} {query} /></button>
  {:else}
    <span data-icon={page.icon || undefined} class={page.icon ? 'before:mr-1.5 before:content-[attr(data-icon)]' : ''}><Highlight text={page.title} {query} /></span>
  {/if}
{/snippet}

{#snippet tagChips()}
  {#each page.tags as id (id)}
    {@const tag = tags.find((t) => t.id === id)}
    {#if tag}
      <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 font-mono text-xs {TAG_STYLE[tag.color].chip}">
        <span class="size-1.5 rounded-full {TAG_STYLE[tag.color].dot}"></span>{tag.name}
      </span>
    {/if}
  {/each}
{/snippet}

{#snippet pinButton()}
  {#if !trashed}
    <button
      type="button"
      class="relative z-10 grid size-9 shrink-0 place-items-center rounded-field hover:bg-line/50 {page.pinned ? 'text-accent-text' : `text-muted opacity-0 ${reveal}`}"
      aria-pressed={page.pinned}
      aria-label="{page.pinned ? 'Desafixar' : 'Fixar'} {page.title}"
      onclick={onpin}
    >
      <Icon name="pin" size={16} />
    </button>
  {/if}
{/snippet}

{#snippet trashButton()}
  {#if !trashed}
    <button
      type="button"
      class="relative z-10 grid size-9 shrink-0 place-items-center rounded-field text-muted opacity-0 hover:bg-line/50 {reveal}"
      aria-label="Mover {page.title} para a lixeira"
      onclick={ontrash}
    >
      <Icon name="trash" size={16} />
    </button>
  {/if}
{/snippet}

{#snippet restoreButton()}
  {#if trashed}
    <button type="button" class="relative z-10 inline-flex items-center justify-center gap-2 rounded-field border border-field-line px-3 py-2 text-sm hover:bg-line/40" onclick={onrestore}>
      <Icon name="restore" size={16} />Restaurar <span class="sr-only">{page.title}</span>
    </button>
  {/if}
{/snippet}

{#if list}
  <article class="group relative flex items-center gap-3 rounded-field border border-line bg-surface py-2 pr-2 pl-4 transition-colors hover:border-field-line" data-testid="page-card">
    <div class="min-w-0 flex-1">
      <h3 class="truncate font-serif text-lg font-semibold">
        {@render title()}
        {#if page.locked}<span class="ml-1 inline-block align-middle text-muted"><Icon name="lock" size={14} /><span class="sr-only">No cofre</span></span>{/if}
        {#if page.shares.length}<span class="ml-1 inline-block align-middle text-muted"><Icon name="people" size={14} /><span class="sr-only">Compartilhada com {page.shares.length} {page.shares.length === 1 ? 'pessoa' : 'pessoas'}</span></span>{/if}
      </h3>
      <p class="truncate text-sm text-muted"><Highlight text={excerpt} {query} /></p>
    </div>
    <div class="hidden shrink-0 gap-2 lg:flex">{@render tagChips()}</div>
    <span class="hidden shrink-0 font-mono text-xs text-muted sm:block">{formatDate(page.updated)}</span>
    {@render restoreButton()}
    {@render pinButton()}
    {@render trashButton()}
  </article>
{:else}
  <article class="group relative flex flex-col rounded-field border border-line bg-surface p-5 transition-colors hover:border-field-line" data-testid="page-card">
    <div class="flex items-start justify-between gap-3">
      <h3 class="font-serif text-xl leading-snug font-semibold wrap-anywhere">{@render title()}</h3>
      <div class="-mt-1.5 -mr-2 flex shrink-0 items-center">
        {#if page.locked}
          <span class="grid size-9 place-items-center text-muted" title="No cofre"><Icon name="lock" size={16} /><span class="sr-only">No cofre</span></span>
        {/if}
        {#if page.shares.length}
          <span class="grid size-9 place-items-center text-muted" title="Compartilhada com {page.shares.length}"><Icon name="people" size={16} /><span class="sr-only">Compartilhada com {page.shares.length} {page.shares.length === 1 ? 'pessoa' : 'pessoas'}</span></span>
        {/if}
        {@render pinButton()}
      </div>
    </div>
    <p class="mt-2 line-clamp-3 min-h-[3lh] text-sm leading-relaxed text-muted">
      <Highlight text={excerpt} {query} />
    </p>
    <div class="mt-4 flex min-h-7 flex-wrap gap-2">{@render tagChips()}</div>
    <div class="mt-4 flex items-center gap-2 border-t border-line pt-3 font-mono text-xs text-muted">
      <span>{formatDate(page.updated)}</span>
      <span class="ml-auto">{pageMeta(page)}</span>
      <span class="-my-2 -mr-2">{@render trashButton()}</span>
    </div>
    {#if trashed}<div class="mt-3 flex flex-col">{@render restoreButton()}</div>{/if}
  </article>
{/if}
