<script lang="ts">
  import { MediaQuery } from 'svelte/reactivity'
  import AuthForm from '../lib/components/auth/AuthForm.svelte'
  import AddServerModal from '../lib/components/auth/AddServerModal.svelte'
  import ConfirmServerModal from '../lib/components/auth/ConfirmServerModal.svelte'
  import AuthHeader from '../lib/components/auth/AuthHeader.svelte'
  import DesktopPanel from '../lib/components/auth/DesktopPanel.svelte'
  import { directory, selection } from '../lib/stores/servers.svelte'
  import { manual } from '../lib/stores/manual.svelte'
  import { fade as fadeTransition } from 'svelte/transition'
  import StatusDot from '../lib/components/auth/StatusDot.svelte'
  import SecureNotice from '../lib/components/auth/SecureNotice.svelte'
  import { ms } from '../lib/motion'
  import { toast } from '../lib/stores/toast.svelte'

  interface Props {
    oncontinueoffline?: () => void
  }

  let { oncontinueoffline }: Props = $props()

  // Same breakpoint (840) as the mobile AuthPage.
  const desktop = new MediaQuery('min-width: 840px')

  // polls the gateway while the login screen exists
  $effect(() => directory.start())
  // and this page's server, for the dot and the footer
  $effect(() => selection.watchHealth())
  // and the servers the user added, each checked on its own
  $effect(() => manual.start())

  // during the server switch the form fades and does not accept taps
  const fade = 'transition-opacity duration-300 motion-reduce:transition-none'

  let adding = $state(false)
  const addServer = () => (adding = true)
</script>

<!-- first stop of the keyboard: jump over the server selector straight to the form -->
<a
  href="#entrar"
  class="sr-only z-50 rounded-field bg-cream px-4 py-2 font-semibold text-on-cream focus:not-sr-only focus:fixed focus:top-3 focus:left-3"
  onclick={(e) => {
    e.preventDefault()
    document.getElementById('entrar')?.querySelector<HTMLElement>('input, button')?.focus()
  }}
>
  Ir para o formulário
</a>

<!-- while a dialog is open the page behind is out of reach (keyboard, pointer and screen reader alike) -->
<main class="min-h-screen bg-bg" inert={adding || !!selection.pendingChange}>
  {#if desktop.current}
    <div class="grid min-h-screen grid-cols-[11fr_12fr]">
      <DesktopPanel onaddserver={addServer} />
      <div class="flex flex-col">
        <div class="flex flex-1 items-center justify-center px-12 py-8">
          <div id="entrar" class="w-full max-w-[480px] {fade} {selection.connecting ? 'opacity-30' : ''}" inert={!!selection.connecting}>
            <AuthForm showSubtitle {oncontinueoffline} />
          </div>
        </div>
        <p class="flex items-center justify-center gap-2.5 px-6 pb-8 font-mono text-xs tracking-[0.6px] text-muted">
          <StatusDot
            tone={selection.health === 'connected' ? 'online' : 'offline'}
            fontSize={12}
            testid="footer-dot"
          />
          <span class="truncate">
            {selection.health === 'connected' ? '→ Rodando em:' : '→ Desconectado de:'}
            {selection.shownAddress}
          </span>
        </p>
        <div class="px-6 pb-6"><SecureNotice /></div>
      </div>
    </div>
  {:else}
    <AuthHeader onaddserver={addServer} />
    <div id="entrar" class="mx-auto max-w-[480px] px-6 pt-7 pb-6 {fade} {selection.connecting ? 'opacity-30' : ''}" inert={!!selection.connecting}>
      <AuthForm {oncontinueoffline} />
    </div>
    <div class="px-6 pb-8"><SecureNotice /></div>
  {/if}
</main>

{#if adding}
  <AddServerModal onclose={() => (adding = false)} />
{/if}

{#if selection.pendingChange}
  <ConfirmServerModal
    name={selection.pendingChange.name}
    onconfirm={() => selection.confirmChange()}
    oncancel={() => selection.cancelChange()}
  />
{/if}

{#if toast.message}
  <div
    role="status"
    transition:fadeTransition={{ duration: ms(200) }}
    class="fixed bottom-6 left-1/2 z-40 -translate-x-1/2 rounded-field border border-line bg-surface px-4 py-3 text-fg"
  >
    {toast.message}
  </div>
{/if}
