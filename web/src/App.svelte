<script lang="ts">
  import { seedLoad, signInFromAddress } from './lib/loadtest'
  import { selection } from './lib/stores/servers.svelte'
  import { Nav } from './lib/stores/nav.svelte'
  import { Workspace } from './lib/stores/workspace.svelte'
  import Dashboard from './routes/Dashboard.svelte'
  import Editor from './routes/Editor.svelte'
  import Login from './routes/Login.svelte'

  // No account flow yet: "Continuar offline" (or `?tela=painel`) shows the dashboard and `/notes/:id` its pages. The
  // flag lives in the address so a reload or the back button keeps the person where they were.
  const inPanel = () => new URLSearchParams(location.search).get('tela') === 'painel'
  const isOffline = () => new URLSearchParams(location.search).get('modo') === 'offline'
  let preview = $state(inPanel())
  window.addEventListener('popstate', () => {
    preview = inPanel()
    if (preview && isOffline() && !ws.offline) ws.goOffline()
  })

  function continueOffline() {
    history.pushState(null, '', '/?tela=painel&modo=offline')
    preview = true
    ws.goOffline()
  }

  function login() {
    history.pushState(null, '', '/')
    preview = false
    ws.offline = false
  }
  const ws = new Workspace()
  if (inPanel() && isOffline()) ws.goOffline()
  // memory measurements only (a build with --mode loadtest); this branch is removed from every other build
  if (import.meta.env.MODE === 'loadtest') {
    seedLoad(ws, new URLSearchParams(location.search))
    signInFromAddress(new URLSearchParams(location.search))
  }
  const nav = new Nav()
  // offline, the account chip shows this server's address: keep checking it while the panel is open
  $effect(() => (preview && ws.offline ? selection.watchHealth() : undefined))
</script>

<!-- There is no router yet: `/` and `/login` (the only routes allowed in isWebRoute) open the Login. -->
{#if preview}
  {#key nav.noteId}
    {#if nav.noteId}
      <Editor {ws} id={nav.noteId} onback={() => nav.back()} onopen={(id) => nav.open(id)} />
    {:else}
      <Dashboard {ws} onopen={(id) => nav.open(id)} {...ws.offline ? { userName: 'Você', server: selection.shownAddress, onlogout: login } : {}} />
    {/if}
  {/key}
{:else}
  <Login oncontinueoffline={continueOffline} />
{/if}
