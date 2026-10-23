<script lang="ts">
  import { MediaQuery } from 'svelte/reactivity'
  import AuthForm from '../lib/components/auth/AuthForm.svelte'
  import AuthHeader from '../lib/components/auth/AuthHeader.svelte'
  import DesktopPanel from '../lib/components/auth/DesktopPanel.svelte'
  import { directory, selection } from '../lib/stores/servers.svelte'
  import { toast } from '../lib/stores/toast.svelte'

  interface Props {
    oncontinueoffline?: () => void
  }

  let { oncontinueoffline }: Props = $props()

  // Mesmo ponto de quebra (840) da AuthPage do mobile.
  const desktop = new MediaQuery('min-width: 840px')

  // consulta o gateway enquanto a tela de login existe
  $effect(() => directory.start())

  // durante a troca de servidor o formulário esmaece e não aceita toques
  const fade = 'transition-opacity duration-300 motion-reduce:transition-none'

  const addServer = () => toast.show('Adicionar servidor chega em breve.')
</script>

<main class="min-h-screen bg-bg">
  {#if desktop.current}
    <div class="grid min-h-screen grid-cols-[11fr_12fr]">
      <DesktopPanel onaddserver={addServer} />
      <div class="flex flex-col">
        <div class="flex flex-1 items-center justify-center px-12 py-8">
          <div class="w-full max-w-[480px] {fade} {selection.connecting ? 'opacity-30' : ''}" inert={!!selection.connecting}>
            <AuthForm showSubtitle {oncontinueoffline} />
          </div>
        </div>
        <p class="pb-8 text-center font-mono text-xs tracking-[0.6px] text-muted">
          → Rodando em: {selection.selected.address}
        </p>
      </div>
    </div>
  {:else}
    <AuthHeader onaddserver={addServer} />
    <div class="mx-auto max-w-[480px] px-6 pt-7 pb-6 {fade} {selection.connecting ? 'opacity-30' : ''}" inert={!!selection.connecting}>
      <AuthForm {oncontinueoffline} />
    </div>
  {/if}
</main>

{#if toast.message}
  <div
    role="status"
    class="fixed bottom-6 left-1/2 z-40 -translate-x-1/2 rounded-field border border-line bg-surface px-4 py-3 text-fg"
  >
    {toast.message}
  </div>
{/if}
