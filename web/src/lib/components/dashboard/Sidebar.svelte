<script lang="ts">
  import { canVault } from '../../capabilities'
  import Icon, { type IconName } from './Icon.svelte'
  import { COLOR_LABEL, TAG_STYLE } from './tags'
  import { TAG_COLORS, type Tag, type TagColor, type View } from '../../stores/workspace.svelte'

  interface Props {
    /** `full`: names and counts; `rail`: icons only (medium screens). */
    mode: 'full' | 'rail'
    view: View
    counts: Record<View, number>
    tags: Tag[]
    tagCounts: Record<string, number>
    tagFilter: string | null
    syncLabel: string
    /** No server: nobody to share with, so "Compartilhadas comigo" is not offered. The vault stays: it is the person's own. */
    local?: boolean
    onview: (view: View) => void
    onnew: () => void
    ontag: (id: string) => void
    onaddtag: (name: string, color: TagColor) => void
    onclose?: () => void
  }

  let { mode, view, counts, tags, tagCounts, tagFilter, syncLabel, local = false, onview, onnew, ontag, onaddtag, onclose }: Props = $props()

  const items: { id: View; label: string; icon: IconName }[] = [
    { id: 'all', label: 'Todas as páginas', icon: 'page' },
    { id: 'shared', label: 'Compartilhadas comigo', icon: 'people' },
    { id: 'vault', label: 'Cofre', icon: 'lock' },
    { id: 'trash', label: 'Lixeira', icon: 'trash' },
  ]

  // no vault on a page without crypto.subtle (plain HTTP), and no sharing without a server
  const shownItems = $derived(items.filter((i) => (i.id !== 'shared' || !local) && (i.id !== 'vault' || canVault())))
  const rail = $derived(mode === 'rail')
  let adding = $state(false)
  let draft = $state('')
  let color = $state<TagColor>('accent')

  function submitTag(e: SubmitEvent) {
    e.preventDefault()
    onaddtag(draft, color)
    draft = ''
    color = 'accent'
    adding = false
  }

  function focusOnMount(node: HTMLInputElement) {
    node.focus()
  }
</script>

<nav aria-label="Navegação principal" class="flex h-full min-h-0 flex-col bg-surface {rail ? 'w-[72px] items-center px-2' : 'w-full px-4'} py-5">
  <div class="flex items-center {rail ? 'justify-center' : 'justify-between'} pb-5">
    <div class="flex items-baseline gap-2">
      {#if rail}
        <span class="grid size-10 place-items-center rounded-field bg-accent font-serif text-xl font-bold" aria-label="Pindrel">P</span>
      {:else}
        <span class="font-serif text-3xl font-bold">Pindrel</span>
        <span class="font-mono text-[10px] tracking-[0.18em] text-muted">SELF-HOSTED</span>
      {/if}
    </div>
    {#if onclose}
      <button type="button" class="grid size-9 place-items-center rounded-field text-muted hover:bg-line/50" aria-label="Fechar menu" onclick={onclose}>
        <Icon name="close" />
      </button>
    {/if}
  </div>

  <button
    type="button"
    class="flex items-center justify-center gap-2 rounded-field bg-cream font-medium text-on-cream hover:bg-cream/90 {rail ? 'size-11' : 'h-11 w-full'}"
    aria-label="Nova página"
    onclick={onnew}
  >
    <Icon name="plus" />{#if !rail}Nova página{/if}
  </button>

  <ul class="mt-5 flex flex-col gap-1 {rail ? '' : 'w-full'}">
    {#each shownItems as item (item.id)}
      {@const current = view === item.id}
      <li>
        <button
          type="button"
          class="flex items-center gap-3 rounded-field text-left transition-colors hover:bg-line/50 {current ? 'bg-accent/45 text-accent-text' : 'text-fg'} {rail ? 'size-11 justify-center' : 'h-11 w-full px-3'}"
          aria-current={current ? 'page' : undefined}
          aria-label={rail ? item.label : undefined}
          title={rail ? item.label : undefined}
          onclick={() => onview(item.id)}
        >
          <Icon name={item.icon} />
          {#if !rail}
            <span class="flex-1 truncate">{item.label}</span>
            <span class="font-mono text-xs {current ? 'text-accent-text' : 'text-muted'}">{counts[item.id]}</span>
          {/if}
        </button>
      </li>
    {/each}
  </ul>

  <div class="my-5 border-t border-line {rail ? 'w-full' : ''}"></div>

  <div class="flex min-h-0 flex-1 flex-col {rail ? 'items-center' : ''}">
    {#if !rail}
      <div class="flex items-center justify-between px-3 pb-2 font-mono text-[11px] tracking-[0.18em] text-muted">
        <span>TAGS <span class="ml-1">{tags.length}</span></span>
        <button type="button" class="grid size-7 place-items-center rounded-field text-accent-text hover:bg-line/50" aria-label="Nova tag" aria-expanded={adding} onclick={() => (adding = !adding)}>
          <Icon name="plus" size={16} />
        </button>
      </div>
      {#if adding}
        <form class="px-3 pb-2" onsubmit={submitTag}>
          <input
            use:focusOnMount
            bind:value={draft}
            maxlength="24"
            aria-label="Nome da nova tag"
            placeholder="nome da tag"
            class="h-9 w-full rounded-field border border-field-line bg-bg px-3 text-sm placeholder:text-muted"
            onkeydown={(e) => e.key === 'Escape' && (adding = false)}
          />
          <div class="mt-2 flex gap-2" role="group" aria-label="Cor da tag">
            {#each TAG_COLORS as c (c)}
              <button
                type="button"
                class="size-6 rounded-full border-2 {TAG_STYLE[c].swatch} {color === c ? 'border-fg' : 'border-transparent'}"
                aria-label="Cor {COLOR_LABEL[c]}"
                aria-pressed={color === c}
                onclick={() => (color = c)}
              ></button>
            {/each}
          </div>
          <div class="mt-3 flex gap-2">
            <button type="submit" class="h-8 rounded-field bg-accent px-3 text-xs hover:bg-accent/85">Criar</button>
            <button type="button" class="h-8 rounded-field border border-field-line px-3 text-xs hover:bg-line/40" onclick={() => (adding = false)}>Cancelar</button>
          </div>
        </form>
      {/if}
    {/if}
    <ul class="flex min-h-0 flex-col gap-1 overflow-y-auto {rail ? 'items-center' : ''}">
      {#each tags as tag (tag.id)}
        {@const on = tagFilter === tag.id}
        <li>
          <button
            type="button"
            class="flex items-center gap-3 rounded-field text-left hover:bg-line/50 {on ? 'bg-line/60' : ''} {rail ? 'size-11 justify-center' : 'h-10 w-full px-3'}"
            aria-pressed={on}
            aria-label={rail ? `Filtrar pela tag ${tag.name}` : undefined}
            title={rail ? tag.name : undefined}
            onclick={() => ontag(tag.id)}
          >
            <span class="size-2.5 shrink-0 rounded-full {TAG_STYLE[tag.color].dot}"></span>
            {#if !rail}
              <span class="flex-1 truncate">{tag.name}</span>
              <span class="font-mono text-xs text-muted">{tagCounts[tag.id] ?? 0}</span>
            {/if}
          </button>
        </li>
      {/each}
    </ul>
  </div>

  <div class="mt-4 flex items-center gap-2 border-t border-line pt-4 font-mono text-xs text-muted {rail ? 'justify-center' : 'px-3'}" role="status">
    <span class="size-2 shrink-0 rounded-full bg-accent-line"></span>
    {#if rail}<span class="sr-only">{syncLabel}</span>{:else}{syncLabel}{/if}
  </div>
</nav>
