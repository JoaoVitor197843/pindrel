<script lang="ts">
  import { tick } from 'svelte'
  import { MediaQuery } from 'svelte/reactivity'
  import Icon from '../lib/components/dashboard/Icon.svelte'
  import Lazy from '../lib/components/dashboard/Lazy.svelte'
  import PageCard from '../lib/components/dashboard/PageCard.svelte'
  import Palette from '../lib/components/dashboard/Palette.svelte'
  import SettingsModal, { type SettingsSection } from '../lib/components/dashboard/SettingsModal.svelte'
  import Sidebar from '../lib/components/dashboard/Sidebar.svelte'
  import TopBar from '../lib/components/dashboard/TopBar.svelte'
  import VaultPrompt from '../lib/components/dashboard/VaultPrompt.svelte'
  import VaultView from '../lib/components/dashboard/VaultView.svelte'
  import { toast } from '../lib/stores/toast.svelte'
  import { download, readImports, toJson, toMarkdown } from '../lib/stores/transfer'
  import { Workspace, type TagColor, type View } from '../lib/stores/workspace.svelte'

  interface Props {
    userName?: string
    /** The account's e-mail; without it one is made up from the name and the server (the demo). */
    email?: string
    server?: string
    onlogout?: () => void
    /** Shared with the editor, so what is edited there shows here. */
    ws?: Workspace
    onopen?: (id: string) => void
  }

  let { userName = 'Marina Reis', email: given_email, server = 'pindrel.local', onlogout, ws: given, onopen }: Props = $props()

  // svelte-ignore state_referenced_locally
  const ws = given ?? new Workspace()
  const desktop = new MediaQuery('min-width: 840px')
  const wide = new MediaQuery('min-width: 1180px')

  let drawer = $state(false)
  let list: HTMLElement | undefined = $state()
  let paletteOpen = $state(false)
  /** The password prompt: what it is for, and the page to open once the vault is unlocked. */
  let vaultPrompt = $state<{ target: string; open: string | null; create?: boolean } | null>(null)
  let settingsOpen = $state(false)
  let section = $state<SettingsSection>('general')

  // Medium screens: a rail of icons that opens over the page (hover, keyboard focus, or a click that pins it).
  let railHover = $state(false)
  let railFocus = $state(false)
  let railPinned = $state(false)
  const rail = $derived(desktop.current && !wide.current)
  const railOpen = $derived(rail && (railHover || railFocus || railPinned))

  const titles: Record<Exclude<View, 'vault'>, string> = { all: 'Minhas páginas', shared: 'Compartilhadas comigo', trash: 'Lixeira' }
  const filterTag = $derived(ws.tagFilter ? ws.tag(ws.tagFilter) : undefined)
  const heading = $derived(ws.view === 'vault' ? 'Cofre' : filterTag ? `#${filterTag.name}` : titles[ws.view])
  const total = $derived(ws.view === 'vault' ? ws.visibleVault.length : ws.visible.length)
  const noun = $derived(ws.view === 'vault' ? (total === 1 ? 'entrada' : 'entradas') : total === 1 ? 'página' : 'páginas')
  const filtering = $derived(!!ws.query.trim() || !!ws.tagFilter)
  const email = $derived(given_email ?? `${userName.trim().split(/\s+/)[0]?.toLowerCase() || 'conta'}@${server}`)

  // without a login there is no "shared with me" list to stay on
  $effect(() => {
    if (ws.local && ws.view === 'shared') ws.go('all')
  })

  // a layout change must not leave the drawer or the rail stuck open
  $effect(() => {
    if (desktop.current) drawer = false
    if (!rail) railHover = railFocus = railPinned = false
  })

  function view(v: View) {
    ws.go(v)
    drawer = false
  }

  async function create() {
    ws.newPage()
    drawer = false
    paletteOpen = false
    await tick()
    list?.querySelector<HTMLElement>('[data-testid="page-card"]')?.scrollIntoView?.({ block: 'nearest' })
    toast.show('Página criada')
  }

  function openSettings(s: SettingsSection = 'general') {
    section = s
    paletteOpen = false
    settingsOpen = true
  }

  /** Opens a page in the editor; one in the vault asks for the master password first. */
  function openPage(id: string) {
    if (!onopen) return
    if (ws.page(id)?.locked && !ws.vaultUnlocked) vaultPrompt = { target: ws.page(id)!.title, open: id }
    else onopen(id)
  }

  function unlock(password: string): boolean {
    if (ws.unlockVault(password) !== 'ok') return false
    const then = vaultPrompt
    vaultPrompt = null
    toast.show('Cofre desbloqueado')
    if (then?.open) onopen?.(then.open)
    else if (then?.create) addVaultEntry()
    return true
  }

  function addVaultEntry() {
    const made = ws.addVaultEntry()
    if (made) onopen?.(made.id)
  }

  function logout() {
    if (onlogout) onlogout()
    else toast.show(ws.local ? 'Entrar em uma conta ainda não está ligado ao login' : 'Sair ainda não está ligado ao login')
  }

  async function exportAll(format: 'json' | 'md') {
    // the list holds no bodies: they are read from the browser's storage for the time the file takes to build
    const ok = await ws.withBodies(() =>
      format === 'json' ? download('pindrel.json', toJson(ws.pages, ws.tags), 'application/json') : download('pindrel.md', toMarkdown(ws.pages, ws.tags), 'text/markdown'),
    )
    toast.show(ok ? 'Exportação pronta' : 'Não foi possível exportar')
  }

  async function importFiles(files: File[]) {
    if (!files.length) return
    const { pages, skipped } = await readImports(files)
    for (const p of pages) ws.newPage(p.title).excerpt = p.excerpt
    toast.show(
      pages.length
        ? `${pages.length} ${pages.length === 1 ? 'página importada' : 'páginas importadas'}${skipped ? `, ${skipped} ignorada${skipped === 1 ? '' : 's'}` : ''}`
        : 'Nenhum arquivo .md ou .txt válido',
    )
  }

  const empty = $derived.by(() => {
    if (filtering)
      return { title: 'Nada encontrado', body: 'Nenhuma página corresponde a esse filtro. Tente outro termo ou limpe a tag selecionada.', cta: 'Limpar filtros', run: () => ws.clearFilters() }
    if (ws.view === 'shared') return { title: 'Nada compartilhado com você', body: 'Quando alguém te der acesso a uma página, ela aparece aqui.', cta: '', run: () => {} }
    if (ws.view === 'trash')
      return {
        title: 'Lixeira vazia',
        body: ws.settings.useTrash
          ? `Páginas excluídas ficam aqui por ${ws.settings.retention} dias antes de sumirem de vez.`
          : 'A lixeira está desligada nas configurações: páginas excluídas somem na hora.',
        cta: '',
        run: () => {},
      }
    return { title: 'Nenhuma página ainda', body: 'Comece um documento em branco — títulos, listas e tags entram depois, no seu ritmo.', cta: 'Criar primeira página', run: () => void create() }
  })

  const sidebarProps = $derived({
    view: ws.view,
    counts: ws.counts,
    tags: ws.tags,
    tagCounts: ws.tagCounts,
    tagFilter: ws.tagFilter,
    syncLabel: 'sync · há 2 min',
    local: ws.local,
    onview: view,
    onnew: create,
    ontag: (id: string) => {
      ws.toggleTagFilter(id)
      drawer = false
    },
    onaddtag: (name: string, color: TagColor) => ws.addTag(name, color),
  })
</script>

<svelte:window
  onkeydown={(e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault()
      paletteOpen = !paletteOpen
    } else if (e.key === 'Escape' && drawer) drawer = false
  }}
  onmousedown={(e) => railPinned && !(e.target as Element).closest?.('[data-rail]') && (railPinned = false)}
/>

<div class="flex h-dvh bg-bg text-fg">
  {#if desktop.current && wide.current}
    <aside class="w-72 shrink-0 border-r border-line">
      <Sidebar mode="full" {...sidebarProps} />
    </aside>
  {:else if desktop.current}
    <div class="relative w-[72px] shrink-0">
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions, a11y_click_events_have_key_events -->
      <aside
        data-rail
        data-open={railOpen}
        class="absolute inset-y-0 left-0 z-20 overflow-hidden border-r border-line bg-surface transition-[width,box-shadow] duration-150 {railOpen ? 'w-72 shadow-2xl' : 'w-[72px]'}"
        onmouseenter={() => (railHover = true)}
        onmouseleave={() => {
          railHover = false
          railPinned = false
        }}
        onfocusin={() => (railFocus = true)}
        onfocusout={(e) => !e.currentTarget.contains(e.relatedTarget as Node) && (railFocus = false)}
        onclick={() => (railPinned = true)}
      >
        <Sidebar mode={railOpen ? 'full' : 'rail'} {...sidebarProps} />
      </aside>
    </div>
  {:else if drawer}
    <button type="button" class="fixed inset-0 z-40 bg-bg/70" aria-label="Fechar menu" tabindex="-1" onclick={() => (drawer = false)}></button>
    <aside class="fixed inset-y-0 left-0 z-50 w-[min(20rem,85vw)] border-r border-line" aria-label="Menu">
      <Sidebar mode="full" {...sidebarProps} onclose={() => (drawer = false)} />
    </aside>
  {/if}

  <div class="flex min-w-0 flex-1 flex-col">
    <TopBar
      bind:query={ws.query}
      compact={!desktop.current}
      showMenuButton={!desktop.current}
      {userName}
      {server}
      onmenu={() => (drawer = true)}
      onpalette={() => (paletteOpen = true)}
      onsettings={() => openSettings('general')}
      onexport={() => openSettings('data')}
      onlogout={logout}
      logoutLabel={ws.local ? 'Logar' : 'Sair'}
    />

    <main class="min-h-0 flex-1 overflow-y-auto px-4 py-6 md:px-8" bind:this={list}>
      {#if ws.view === 'vault'}
        <VaultView
          pages={ws.visibleVault}
          unlocked={ws.vaultUnlocked}
          onlock={() => ws.lockVault()}
          onunlock={(target) => (vaultPrompt = { target, open: null, create: target === 'uma nova entrada' })}
          onopen={(page) => (onopen ? openPage(page.id) : ws.vaultUnlocked || (vaultPrompt = { target: page.title, open: null }))}
          onadd={addVaultEntry}
        />
      {:else}
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1">
            <h1 class="font-serif text-3xl font-bold md:text-4xl">{heading}</h1>
            <span class="font-mono text-sm text-muted" role="status">{total} {noun}</span>
          </div>
          <div class="flex items-center gap-2">
            {#if ws.view === 'trash' && total > 0}
              <button type="button" class="h-10 rounded-field border border-field-line px-3 text-sm hover:bg-line/40" onclick={() => ws.emptyTrash()}>Esvaziar lixeira</button>
            {/if}
            <div class="inline-flex rounded-field border border-line p-1" role="group" aria-label="Visualização">
              {#each [['grid', 'Grade'], ['list', 'Lista']] as [id, label] (id)}
                <button
                  type="button"
                  class="grid size-8 place-items-center rounded-[7px] {ws.layout === id ? 'bg-line text-fg' : 'text-muted hover:text-fg'}"
                  aria-pressed={ws.layout === id}
                  aria-label={label}
                  title={label}
                  onclick={() => (ws.layout = id as 'grid' | 'list')}
                >
                  <Icon name={id as 'grid' | 'list'} size={16} />
                </button>
              {/each}
            </div>
            <div class="inline-flex rounded-field border border-line p-1 font-mono text-xs tracking-[0.12em]" role="group" aria-label="Ordenar">
              {#each [['recent', 'RECENTES'], ['az', 'A–Z']] as [id, label] (id)}
                <button
                  type="button"
                  class="rounded-[7px] px-3 py-2 {ws.sort === id ? 'bg-cream text-on-cream' : 'text-muted hover:text-fg'}"
                  aria-pressed={ws.sort === id}
                  onclick={() => (ws.sort = id as 'recent' | 'az')}
                >
                  {label}
                </button>
              {/each}
            </div>
          </div>
        </div>

        {#if filterTag}
          <button type="button" class="mt-4 inline-flex items-center gap-2 rounded-full border border-field-line px-3 py-1 font-mono text-xs hover:bg-line/40" onclick={() => (ws.tagFilter = null)}>
            tag: {filterTag.name}<Icon name="close" size={12} /><span class="sr-only">Remover filtro</span>
          </button>
        {/if}

        {#if ws.visible.length === 0 && !ws.loading}
          <div class="mt-8 flex flex-col items-center gap-2 rounded-field border border-dashed border-line p-10 text-center" data-testid="empty">
            <span class="text-muted"><Icon name={filtering ? 'search' : ws.view === 'trash' ? 'trash' : ws.view === 'shared' ? 'people' : 'page'} size={28} /></span>
            <h2 class="font-serif text-2xl">{empty.title}</h2>
            <p class="max-w-md text-sm text-muted">{empty.body}</p>
            {#if empty.cta}
              <button type="button" class="mt-3 inline-flex h-11 items-center gap-2 rounded-field bg-cream px-4 text-sm font-medium text-on-cream hover:bg-cream/90" onclick={empty.run}>
                {#if !filtering}<Icon name="plus" size={16} />{/if}{empty.cta}
              </button>
            {/if}
          </div>
        {:else}
          {#each ws.groups as group (group.key)}
            <section class="mt-6" aria-labelledby="g-{group.key}">
              <h2
                id="g-{group.key}"
                class={group.label ? 'mb-3 flex items-center gap-3 font-mono text-[11px] tracking-[0.18em] text-muted uppercase' : 'sr-only'}
              >
                {group.label ?? 'Resultados'}
                {#if group.label}<span class="h-px flex-1 bg-line"></span><span>{group.pages.length}</span>{/if}
              </h2>
              <div class={ws.layout === 'grid' ? 'grid gap-4 md:grid-cols-2 xl:grid-cols-3' : 'flex flex-col gap-2'}>
                {#each group.pages as page, i (page.id)}
                  <Lazy id={page.id} estimate={ws.layout === 'grid' ? 200 : 64} eager={i < 18}>
                  <PageCard
                    {page}
                    tags={ws.tags}
                    layout={ws.layout}
                    query={ws.query}
                    trashed={ws.view === 'trash'}
                    onpin={() => ws.togglePin(page.id)}
                    ontrash={() => {
                      ws.trash(page.id)
                      toast.show(ws.settings.useTrash ? 'Movida para a lixeira' : 'Página excluída')
                    }}
                    onrestore={() => ws.restore(page.id)}
                    vaultUnlocked={ws.vaultUnlocked}
                    onopen={onopen ? () => openPage(page.id) : undefined}
                  />
                  </Lazy>
                {/each}
              </div>
            </section>
          {/each}
        {/if}
      {/if}
    </main>
  </div>

  {#if paletteOpen}
    <Palette {ws} actions={{
        newPage: () => void create(),
        openSettings: () => openSettings('general'),
        close: () => (paletteOpen = false),
        open: onopen && ((id) => ((paletteOpen = false), openPage(id))),
      }} onclose={() => (paletteOpen = false)} />
  {/if}

  {#if vaultPrompt}
    <VaultPrompt target={vaultPrompt.target} onunlock={unlock} onclose={() => (vaultPrompt = null)} />
  {/if}

  {#if settingsOpen}
    <SettingsModal
      bind:section
      settings={ws.settings}
      stacked={!desktop.current}
      {userName}
      {email}
      summary={{ pages: ws.counts.all, shared: ws.counts.shared, vault: ws.counts.vault, trashed: ws.counts.trash }}
      onsave={(next) => {
        ws.saveSettings(next)
        toast.show('Configurações salvas')
      }}
      onemptytrash={() => {
        ws.emptyTrash()
        toast.show('Lixeira esvaziada')
      }}
      onexport={exportAll}
      onimport={importFiles}
      onclose={() => (settingsOpen = false)}
    />
  {/if}

  {#if toast.message}
    <div class="fixed bottom-6 left-1/2 z-[80] -translate-x-1/2 rounded-field border border-line bg-surface px-4 py-2 text-sm shadow-lg" role="status">{toast.message}</div>
  {/if}
</div>
