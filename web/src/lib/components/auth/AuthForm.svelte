<script lang="ts">
  import { fade, slide } from 'svelte/transition'
  import { ms } from '../../motion'
  import { toast } from '../../stores/toast.svelte'
  import RecoveryKeyModal from './RecoveryKeyModal.svelte'

  interface Props {
    /** Mostra a linha de apoio sob o título (layout largo). */
    showSubtitle?: boolean
    oncontinueoffline?: () => void
  }

  let { showSubtitle = false, oncontinueoffline }: Props = $props()

  let register = $state(false)
  let obscure = $state(true)
  let keepSignedIn = $state(true)
  let recoveryOpen = $state(false)

  const field =
    'w-full rounded-field border border-line bg-surface px-4 py-4 text-fg placeholder:text-muted transition-colors duration-200 focus:border-accent-line focus:outline-none'

  function continueOffline() {
    if (oncontinueoffline) return oncontinueoffline()
    toast.show('Notas locais chegam em breve.')
  }

  function submit(event: SubmitEvent) {
    // A integração com a API de auth ainda não existe.
    event.preventDefault()
  }
</script>

<div class="flex flex-col gap-5">
  <div>
    <!-- o texto novo aparece com fade (o antigo é trocado na hora, sem os dois empilhados) -->
    {#key register}
      <h1 class="font-serif text-3xl" in:fade={{ duration: ms(200) }}>
        {register ? 'Criar nova conta' : 'Bem-vindo de volta'}
      </h1>
      {#if showSubtitle}
        <p class="mt-2 text-muted" in:fade={{ duration: ms(200) }}>
          {register ? 'Crie sua conta para começar a escrever.' : 'Entre para continuar de onde você parou.'}
        </p>
      {/if}
    {/key}
  </div>

  <form class="flex flex-col gap-5" onsubmit={submit}>
    {#if register}
      <div class="flex flex-col gap-2" transition:slide={{ duration: ms(200) }}>
        <label for="username" class="font-semibold">Username</label>
        <input id="username" type="text" autocomplete="username" placeholder="seu_usuario" class={field} />
      </div>
    {/if}

    <div class="flex flex-col gap-2">
      <label for="email" class="font-semibold">E-mail</label>
      <input id="email" type="email" autocomplete="email" placeholder="voce@casa.local" class={field} />
    </div>

    <div class="flex flex-col gap-2">
      <div class="flex items-center justify-between">
        <label for="password" class="font-semibold">Senha</label>
        <button
          type="button"
          onclick={() => (obscure = !obscure)}
          class="font-mono text-xs uppercase tracking-[1.4px] text-muted transition-colors duration-150 hover:text-fg"
        >
          {obscure ? 'MOSTRAR' : 'OCULTAR'}
        </button>
      </div>
      <input
        id="password"
        type={obscure ? 'password' : 'text'}
        autocomplete={register ? 'new-password' : 'current-password'}
        placeholder="••••••••••"
        class={field}
      />
    </div>

    <div class="flex items-center justify-between gap-2">
      <label class="flex cursor-pointer items-center gap-2.5">
        <input type="checkbox" bind:checked={keepSignedIn} class="peer sr-only" />
        <span
          class="flex size-5 items-center justify-center rounded-sm border border-accent-line transition-colors duration-150 peer-checked:bg-accent peer-focus-visible:ring-2 peer-focus-visible:ring-accent-line {keepSignedIn
            ? ''
            : 'text-transparent'}"
        >
          <svg class="size-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" aria-hidden="true">
            <path d="M20 6 9 17l-5-5" />
          </svg>
        </span>
        <span>Manter conectado</span>
      </label>
      <button type="button" onclick={() => (recoveryOpen = true)} class="text-accent-line transition-opacity duration-150 hover:opacity-80">
        Chave de recuperação
      </button>
    </div>

    <button type="submit" class="h-13.5 rounded-field bg-cream text-base font-semibold text-on-cream transition duration-150 hover:bg-cream/90 active:scale-[0.98]">
      {register ? 'Criar conta' : 'Entrar'}
    </button>
  </form>

  <div class="flex items-center gap-4" role="separator">
    <span class="h-px flex-1 bg-line"></span>
    <span class="font-mono text-[11px] uppercase tracking-[1.4px] text-muted">OU</span>
    <span class="h-px flex-1 bg-line"></span>
  </div>

  <button
    type="button"
    onclick={continueOffline}
    class="h-13.5 rounded-field border border-line text-fg transition duration-150 hover:bg-surface active:scale-[0.98]"
  >
    Continuar offline neste dispositivo
  </button>

  <p class="text-center text-muted">
    {register ? 'Já tem conta?' : 'Ainda não tem conta?'}
    <button type="button" onclick={() => (register = !register)} class="font-bold text-fg">
      {register ? 'Entrar' : 'Criar conta'}
    </button>
  </p>
</div>

{#if recoveryOpen}
  <RecoveryKeyModal onclose={() => (recoveryOpen = false)} />
{/if}
