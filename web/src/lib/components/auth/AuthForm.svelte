<script lang="ts">
  import { fade, slide } from 'svelte/transition'
  import type { Account } from '../../api/auth'
  import { ms } from '../../motion'
  import { auth as defaultAuth, type Auth } from '../../stores/auth.svelte'
  import { selection } from '../../stores/servers.svelte'
  import { toast } from '../../stores/toast.svelte'
  import { AuthApiError } from '../../api/auth'
  import { messageFor, validate, type FormMode } from './authMessages'
  import Checkbox from './Checkbox.svelte'
  import RecoveryKeyModal from './RecoveryKeyModal.svelte'

  interface Props {
    /** Shows the supporting line under the title (wide layout). */
    showSubtitle?: boolean
    oncontinuelocal?: () => void
    /** Runs once the person is signed in (a new account is signed in right after it is created). */
    onsignedin?: (user: Account) => void
    /** The session the form signs into (a test can stand in for it). */
    auth?: Auth
  }

  let { showSubtitle = false, oncontinuelocal, onsignedin, auth = defaultAuth }: Props = $props()

  let register = $state(false)
  let obscure = $state(true)
  let keepSignedIn = $state(true)
  let recoveryOpen = $state(false)

  let email = $state('')
  let username = $state('')
  let password = $state('')
  let busy = $state(false)
  let error = $state('')
  let notice = $state('')
  let invalid = $state<'email' | 'username' | 'password' | null>(null)

  // unknown (null) counts as open: the form must not hide "Criar conta" just because the server has not answered yet
  const registrationOpen = $derived(selection.registrationEnabled !== false)
  $effect(() => {
    if (!registrationOpen) register = false
  })

  const mode = $derived<FormMode>(register ? 'register' : 'login')

  const field =
    'w-full rounded-field border border-field-line bg-surface px-4 py-4 text-fg placeholder:text-muted transition-colors duration-200 focus:border-accent-line focus:outline-none aria-invalid:border-offline'

  function continueLocal() {
    if (oncontinuelocal) return oncontinuelocal()
    toast.show('Notas locais chegam em breve.')
  }

  function switchMode() {
    register = !register
    error = ''
    notice = ''
    invalid = null
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault()
    if (busy) return
    error = notice = ''
    const problem = validate(mode, { email, username, password })
    invalid = problem?.field ?? null
    if (problem) {
      error = problem.message
      document.getElementById(problem.field)?.focus()
      return
    }
    busy = true
    const address = email.trim()
    let created = false
    try {
      if (register) {
        await auth.register(address, username.trim(), password)
        created = true
      }
      const user = await auth.login(address, password, keepSignedIn)
      password = ''
      onsignedin?.(user)
    } catch (e) {
      if (e instanceof AuthApiError && e.code === 'registration_disabled') selection.registrationEnabled = false
      if (created) {
        // the account exists; only the sign-in after it failed
        register = false
        notice = 'Conta criada. Entre com seu e-mail e senha.'
      } else error = messageFor(e, mode)
    } finally {
      busy = false
    }
  }
</script>

<div class="flex flex-col gap-5">
  <div>
    <!-- the new text appears with a fade (the old one is swapped at once, without both stacked) -->
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
        <input id="username" type="text" autocomplete="username" placeholder="seu_usuario" bind:value={username} aria-invalid={invalid === 'username'} class={field} />
      </div>
    {/if}

    <div class="flex flex-col gap-2">
      <label for="email" class="font-semibold">E-mail</label>
      <input id="email" type="email" autocomplete="email" placeholder="voce@casa.local" bind:value={email} aria-invalid={invalid === 'email'} class={field} />
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
        bind:value={password}
        aria-invalid={invalid === 'password'}
        class={field}
      />
    </div>

    <div class="flex items-center justify-between gap-2">
      <label class="flex cursor-pointer items-center gap-2.5">
        <input type="checkbox" bind:checked={keepSignedIn} class="peer sr-only" />
        <span class="rounded-sm peer-focus-visible:ring-2 peer-focus-visible:ring-accent-line">
          <Checkbox checked={keepSignedIn} />
        </span>
        <span>Manter conectado</span>
      </label>
      <button type="button" onclick={() => (recoveryOpen = true)} class="text-accent-line transition-opacity duration-150 hover:opacity-80">
        Chave de recuperação
      </button>
    </div>

    {#if error}
      <p role="alert" class="text-sm break-words text-offline-text" data-testid="form-error">{error}</p>
    {/if}
    {#if notice}
      <p role="status" class="text-sm break-words text-muted" data-testid="form-notice">{notice}</p>
    {/if}

    <button
      type="submit"
      disabled={busy}
      aria-busy={busy}
      class="h-13.5 rounded-field bg-cream text-base font-semibold text-on-cream transition duration-150 hover:bg-cream/90 active:scale-[0.98] disabled:opacity-60 disabled:active:scale-100"
    >
      {busy ? (register ? 'Criando conta…' : 'Entrando…') : register ? 'Criar conta' : 'Entrar'}
    </button>
  </form>

  <div class="flex items-center gap-4" role="separator">
    <span class="h-px flex-1 bg-line"></span>
    <span class="font-mono text-[11px] uppercase tracking-[1.4px] text-muted">OU</span>
    <span class="h-px flex-1 bg-line"></span>
  </div>

  <button
    type="button"
    onclick={continueLocal}
    class="h-13.5 rounded-field border border-field-line text-fg transition duration-150 hover:bg-surface active:scale-[0.98]"
  >
    Continuar sem login
  </button>

  {#if registrationOpen}
    <p class="text-center text-muted">
      {register ? 'Já tem conta?' : 'Ainda não tem conta?'}
      <button type="button" onclick={switchMode} class="font-bold text-fg">
        {register ? 'Entrar' : 'Criar conta'}
      </button>
    </p>
  {:else}
    <p class="text-center text-muted" data-testid="registration-closed">Novos registros estão desativados no momento.</p>
  {/if}
</div>

{#if recoveryOpen}
  <RecoveryKeyModal onclose={() => (recoveryOpen = false)} />
{/if}
