<script lang="ts">
  import { untrack } from 'svelte'
  import { seedLoad, signInFromAddress } from './lib/loadtest'
  import { selection } from './lib/stores/servers.svelte'
  import { Nav } from './lib/stores/nav.svelte'
  import { Workspace } from './lib/stores/workspace.svelte'
  import { NotesStore } from './lib/storage/notesStore'
  import { toast } from './lib/stores/toast.svelte'
  import Dashboard from './routes/Dashboard.svelte'
  import Editor from './routes/Editor.svelte'
  import Login from './routes/Login.svelte'

  // No account flow yet: "Continuar sem login" (or `?tela=painel`) shows the dashboard and `/notes/:id` its pages. The
  // flag lives in the address so a reload or the back button keeps the person where they were.
  const inPanel = () => new URLSearchParams(location.search).get('tela') === 'painel'
  const isLocal = () => new URLSearchParams(location.search).get('modo') === 'local'
  let preview = $state(inPanel())
  window.addEventListener('popstate', () => {
    preview = inPanel()
    if (preview && isLocal() && !ws.local) goLocal()
  })

  /** Opens the browser's storage and brings the saved pages in (the list shows nothing until then, not an empty state). */
  async function openStorage() {
    ws.loading = true
    try {
      await ws.attach(await NotesStore.openLocal())
    } catch (e) {
      console.error(e)
      toast.show('Este navegador não deixou guardar as notas; elas valem só até fechar a aba')
    } finally {
      ws.loading = false
    }
  }

  function goLocal() {
    ws.goLocal()
    void openStorage()
  }

  function continueLocal() {
    history.pushState(null, '', '/?tela=painel&modo=local')
    preview = true
    goLocal()
  }

  function login() {
    history.pushState(null, '', '/')
    preview = false
    ws.local = false
  }
  const ws = new Workspace()
  if (inPanel() && isLocal()) goLocal()
  // memory measurements only (a build with --mode loadtest); this branch is removed from every other build
  if (import.meta.env.MODE === 'loadtest') {
    seedLoad(ws, new URLSearchParams(location.search))
    signInFromAddress(new URLSearchParams(location.search))
  }
  const nav = new Nav()
  // The body of a page is read from the browser's storage before the editor starts (it must never see a page as empty)
  // and leaves memory again, once saved, when its screen closes.
  let unreadable = $state<string | null>(null)
  const noteReady = $derived(!!nav.noteId && !ws.loading && ws.bodyIn(nav.noteId))
  // Two effects on purpose. Letting go must depend on the page id and nothing else: if reading the body re-ran it, the
  // body would be dropped the moment it arrived and the editor would blink in a loop.
  $effect(() => {
    const id = nav.noteId
    if (!id) return
    return () => ws.release(id)
  })
  $effect(() => {
    const id = nav.noteId
    if (!id || ws.loading || ws.bodyIn(id)) return
    untrack(() =>
      void ws.load(id).then((ok) => {
        if (!ok && nav.noteId === id) unreadable = id
      }),
    )
  })
</script>

<!-- There is no router yet: `/` and `/login` (the only routes allowed in isWebRoute) open the Login. -->
{#if preview}
  {#key nav.noteId}
    {#if nav.noteId}
      {#if noteReady}
        <Editor {ws} id={nav.noteId} onback={() => nav.back()} onopen={(id) => nav.open(id)} />
      {:else if unreadable === nav.noteId}
        <main class="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-4 p-6 text-center">
          <p class="text-muted">Não foi possível abrir esta página.</p>
          <button type="button" class="h-11 rounded-field bg-cream px-4 text-sm font-medium text-on-cream" onclick={() => nav.back()}>Voltar</button>
        </main>
      {:else}
        <div class="min-h-dvh bg-bg" aria-busy="true"></div>
      {/if}
    {:else}
      <Dashboard {ws} onopen={(id) => nav.open(id)} {...ws.local ? { userName: 'Você', server: selection.address ?? location.host, onlogout: login } : {}} />
    {/if}
  {/key}
{:else}
  <Login oncontinuelocal={continueLocal} />
{/if}
