<script lang="ts">
  import { untrack } from 'svelte'
  import type { Account } from './lib/api/auth'
  import { seedLoad, signInFromAddress } from './lib/loadtest'
  import { fillSample } from './lib/sample'
  import { selection } from './lib/stores/servers.svelte'
  import { auth } from './lib/stores/auth.svelte'
  import { Nav } from './lib/stores/nav.svelte'
  import { Workspace } from './lib/stores/workspace.svelte'
  import { NotesStore } from './lib/storage/notesStore'
  import { toast } from './lib/stores/toast.svelte'
  import Dashboard from './routes/Dashboard.svelte'
  import Editor from './routes/Editor.svelte'
  import Login from './routes/Login.svelte'

  // Two ways to be in the panel, kept in the address so a reload or the back button keeps the person where they were:
  // `?tela=painel&modo=local` ("Continuar sem login": notes in this browser, no server involved) and `&modo=conta` (a
  // signed-in account, with its own database). Without a mode the address opens the login; only the loadtest build treats
  // `?tela=painel` alone as a panel with sample pages (the memory measurements).
  const params = () => new URLSearchParams(location.search)
  const isLocal = () => params().get('modo') === 'local'
  const isAccount = () => params().get('modo') === 'conta'
  /** The sample panel exists only in the build made for the memory measurements. */
  const isDemo = () => import.meta.env.MODE === 'loadtest' && params().get('modo') === null
  const inPanel = () => params().get('tela') === 'painel' && (isLocal() || isAccount() || isDemo())
  let preview = $state(inPanel())
  /** The account whose database is open, or null. */
  let openAccountId = $state<string | null>(null)
  /** A saved session is being turned back into a live one: neither the login nor the panel may flash meanwhile. */
  let restoring = $state(false)

  window.addEventListener('popstate', () => {
    preview = inPanel()
    if (preview && isLocal() && !ws.local) goLocal()
    if (preview && isAccount()) {
      if (auth.user && auth.status === 'in') {
        if (openAccountId !== auth.user.id) enterAccount(auth.user)
      } else {
        // the session ended while the panel was behind us
        history.replaceState(null, '', '/')
        preview = false
      }
    }
  })

  /** Opens a browser database and brings the saved pages in (the list shows nothing until then, not an empty state). */
  async function openStorage(open: () => Promise<NotesStore>) {
    ws.loading = true
    try {
      await ws.attach(await open())
    } catch (e) {
      console.error(e)
      toast.show('Este navegador não deixou guardar as notas; elas valem só até fechar a aba')
    } finally {
      ws.loading = false
    }
  }

  function goLocal() {
    openAccountId = null
    ws.goLocal()
    ws.ownerName = 'Você'
    void openStorage(() => NotesStore.openLocal())
  }

  function enterAccount(user: Account) {
    openAccountId = user.id
    ws.goAccount()
    ws.ownerName = user.username
    void openStorage(() => NotesStore.openAccount(user.id))
  }

  function continueLocal() {
    history.pushState(null, '', '/?tela=painel&modo=local')
    preview = true
    goLocal()
  }

  function signedIn(user: Account) {
    history.pushState(null, '', '/?tela=painel&modo=conta')
    preview = true
    enterAccount(user)
  }

  /** "Logar" in local mode: back to the login screen. */
  function toLogin() {
    history.pushState(null, '', '/')
    preview = false
    ws.local = false
  }

  function logout() {
    // the account is closed first: the effect below must not take a deliberate sign-out for an expired session
    leaveAccount()
    void auth.logout()
  }

  /** The account is closed: the login screen again, and nothing of its notes left in memory. */
  function leaveAccount() {
    openAccountId = null
    void ws.close()
    history.pushState(null, '', '/')
    preview = false
  }

  const ws = new Workspace()
  if (inPanel() && isLocal()) goLocal()
  // A device that had a session turns it back into one before anything shows. Local mode never asks the server.
  if (!isLocal() && (isAccount() || (auth.remembered && location.pathname === '/' && !inPanel()))) {
    restoring = true
    void auth.restore().then((ok) => {
      restoring = false
      if (ok && auth.user) {
        if (!inPanel() || !isAccount()) history.replaceState(null, '', `${location.pathname === '/' ? '/' : location.pathname}?tela=painel&modo=conta`)
        preview = true
        enterAccount(auth.user)
      } else if (isAccount()) {
        history.replaceState(null, '', '/')
        preview = false
      }
    })
  }
  // a session that ends while the panel is open (the cookie was revoked, or it ran out): back to the login, with a word
  $effect(() => {
    if (openAccountId && auth.status === 'out') {
      toast.show('Sua sessão terminou. Entre de novo.')
      untrack(leaveAccount)
    }
  })
  // only a signed-in page keeps asking the server how it is (local mode never does)
  $effect(() => (preview && auth.status === 'in' && openAccountId ? selection.watchHealth() : undefined))
  // memory measurements only (a build with --mode loadtest); this branch is removed from every other build
  if (import.meta.env.MODE === 'loadtest') {
    if (isDemo() && inPanel()) fillSample(ws)
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
{#if restoring}
  <div class="min-h-dvh bg-bg" aria-busy="true"></div>
{:else if preview}
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
      <Dashboard
        {ws}
        onopen={(id) => nav.open(id)}
        {...ws.local
          ? { userName: 'Você', server: selection.address ?? location.host, onlogout: toLogin }
          : auth.user && openAccountId
            ? { userName: auth.user.username, email: auth.user.email, server: selection.shownAddress, onlogout: logout }
            : {}}
      />
    {/if}
  {/key}
{:else}
  <Login oncontinuelocal={continueLocal} onsignedin={signedIn} />
{/if}
