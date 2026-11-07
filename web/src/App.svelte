<script lang="ts">
  import { seedLoad } from './lib/loadtest'
  import { Nav } from './lib/stores/nav.svelte'
  import { Workspace } from './lib/stores/workspace.svelte'
  import Dashboard from './routes/Dashboard.svelte'
  import Editor from './routes/Editor.svelte'
  import Login from './routes/Login.svelte'

  // Prototype switch: no login flow yet. `?tela=painel` shows the dashboard (and `/notes/:id` its pages) so they can
  // be reviewed on their own.
  const preview = new URLSearchParams(location.search).get('tela') === 'painel'
  const ws = new Workspace()
  // memory measurements only (a build with --mode loadtest); this branch is removed from every other build
  if (import.meta.env.MODE === 'loadtest') seedLoad(ws, new URLSearchParams(location.search))
  const nav = new Nav()
</script>

<!-- There is no router yet: `/` and `/login` (the only routes allowed in isWebRoute) open the Login. -->
{#if preview}
  {#key nav.noteId}
    {#if nav.noteId}
      <Editor {ws} id={nav.noteId} onback={() => nav.back()} onopen={(id) => nav.open(id)} />
    {:else}
      <Dashboard {ws} onopen={(id) => nav.open(id)} />
    {/if}
  {/key}
{:else}
  <Login />
{/if}
