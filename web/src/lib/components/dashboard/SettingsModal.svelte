<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { modal } from '../../a11y/dialog'
  import { ms } from '../../motion'
  import type { Settings } from '../../stores/workspace.svelte'
  import { AI_PROVIDERS } from '../../stores/aiProviders'
  import Icon from './Icon.svelte'

  export type SettingsSection = 'general' | 'account' | 'trash' | 'data' | 'ai'

  interface Props {
    settings: Settings
    section: SettingsSection
    /** Narrow screens: the sections list and the section are two steps of one screen. */
    stacked: boolean
    userName: string
    email: string
    summary: { pages: number; shared: number; vault: number; trashed: number }
    onsave: (next: Settings) => void
    onemptytrash: () => void
    onexport: (format: 'json' | 'md') => void
    onimport: (files: File[]) => void
    onclose: () => void
  }

  let { settings, section = $bindable(), stacked, userName, email, summary, onsave, onemptytrash, onexport, onimport, onclose }: Props = $props()

  const opener = document.activeElement
  const NAV: { id: SettingsSection; label: string }[] = [
    { id: 'general', label: 'Geral' },
    { id: 'account', label: 'Conta' },
    { id: 'trash', label: 'Lixeira' },
    { id: 'data', label: 'Importar/Exportar' },
    { id: 'ai', label: 'IA (opcional)' },
  ]

  // edited copy: nothing changes for the rest of the screen until "Salvar"
  // svelte-ignore state_referenced_locally
  let useTrash = $state(settings.useTrash)
  // svelte-ignore state_referenced_locally
  let retention = $state(settings.retention)
  let dirty = $state(false)
  let atList = $state(true)
  let providerId = $state(AI_PROVIDERS[0].id)
  const provider = $derived(AI_PROVIDERS.find((p) => p.id === providerId) ?? AI_PROVIDERS[0])

  const showList = $derived(!stacked || atList)
  const showPane = $derived(!stacked || !atList)
  const title = $derived(stacked && !atList ? NAV.find((n) => n.id === section)!.label : 'Configurações')

  function pick(id: SettingsSection) {
    section = id
    atList = false
  }

  function save() {
    onsave({ useTrash, retention })
    dirty = false
  }

  function escape(e: KeyboardEvent) {
    if (e.key !== 'Escape') return
    if (stacked && !atList) atList = true
    else onclose()
  }

  function picked(e: Event) {
    const input = e.currentTarget as HTMLInputElement
    onimport([...(input.files ?? [])])
    input.value = ''
  }

  const field = 'h-11 w-full rounded-field border border-field-line bg-bg px-3 text-sm'
</script>

<svelte:window onkeydown={escape} />

<div class="fixed inset-0 z-[70] flex items-center justify-center {stacked ? '' : 'p-6'}" transition:fade|global={{ duration: ms(200) }}>
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="settings-backdrop" class="absolute inset-0 cursor-default bg-black/60" onclick={onclose}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-labelledby="settings-title"
    use:modal={opener}
    transition:fly|global={{ y: 30, duration: ms(220) }}
    class="relative flex w-full flex-col overflow-hidden border border-line bg-surface {stacked ? 'h-dvh rounded-none' : 'h-[min(600px,84dvh)] max-w-3xl rounded-field'}"
  >
    <div class="flex items-center gap-2 border-b border-line px-4 py-3">
      {#if stacked && !atList}
        <button type="button" class="grid size-9 place-items-center rounded-field hover:bg-line/50" aria-label="Voltar para as seções" onclick={() => (atList = true)}>
          <span class="rotate-180"><Icon name="chevron-right" /></span>
        </button>
      {/if}
      <h2 id="settings-title" class="flex-1 font-serif text-xl">{title}</h2>
      <button type="button" class="grid size-9 place-items-center rounded-field text-muted hover:bg-line/50" aria-label="Fechar configurações" onclick={onclose}>
        <Icon name="close" />
      </button>
    </div>

    <div class="flex min-h-0 flex-1">
      {#if showList}
        <ul class="flex shrink-0 flex-col overflow-y-auto {stacked ? 'w-full' : 'w-48 gap-px border-r border-line bg-bg/40 p-2'}" aria-label="Seções">
          {#each NAV as item (item.id)}
            {@const on = !stacked && section === item.id}
            <li class={stacked ? 'border-b border-line' : ''}>
              <button
                type="button"
                class="flex w-full items-center justify-between rounded-field text-left hover:bg-line/40 {stacked ? 'px-5 py-4 text-[15px]' : 'px-3 py-2 text-sm'} {on ? 'bg-line/60 font-medium' : 'text-muted'}"
                aria-current={on ? 'true' : undefined}
                onclick={() => pick(item.id)}
              >
                {item.label}
                {#if stacked}<Icon name="chevron-right" size={16} />{/if}
              </button>
            </li>
          {/each}
        </ul>
      {/if}

      {#if showPane}
        <div class="min-w-0 flex-1 overflow-y-auto p-5 sm:p-7">
          {#if section === 'general'}
            <h3 class="font-serif text-2xl">Geral</h3>
            <p class="mb-5 font-mono text-xs text-muted">preferências desta instância</p>
            <div class="flex flex-col gap-5">
              <label class="flex flex-col gap-2 text-sm">
                Idioma da interface
                <select class={field} onchange={() => (dirty = true)}>
                  <option>Português (Brasil)</option>
                  <option>English</option>
                  <option>Español</option>
                </select>
              </label>
              <div class="flex items-center justify-between gap-4">
                <div id="trash-switch-label">
                  <p class="text-sm">Usar lixeira</p>
                  <p class="text-xs text-muted">Páginas excluídas ficam recuperáveis antes de sumirem.</p>
                </div>
                <button
                  type="button"
                  role="switch"
                  aria-checked={useTrash}
                  aria-labelledby="trash-switch-label"
                  class="flex h-7 w-12 shrink-0 items-center rounded-full border border-field-line px-0.5 {useTrash ? 'justify-end bg-accent' : 'justify-start bg-bg'}"
                  onclick={() => {
                    useTrash = !useTrash
                    dirty = true
                  }}
                >
                  <span class="size-5 rounded-full bg-fg"></span>
                </button>
              </div>
              <div class="flex flex-col gap-2 text-sm {useTrash ? '' : 'opacity-60'}">
                <label for="retention">Dias de retenção da lixeira</label>
                <div class="flex items-center gap-4">
                  <input
                    id="retention"
                    type="range"
                    min="7"
                    max="90"
                    step="1"
                    disabled={!useTrash}
                    bind:value={retention}
                    oninput={() => (dirty = true)}
                    class="min-w-0 flex-1 accent-accent-line"
                  />
                  <span class="w-16 text-right font-mono text-xs text-muted">{retention} dias</span>
                </div>
              </div>
            </div>
          {:else if section === 'account'}
            <h3 class="font-serif text-2xl">Conta</h3>
            <p class="mb-5 font-mono text-xs text-muted">{email}</p>
            <div class="flex flex-col gap-5">
              <label class="flex flex-col gap-2 text-sm">Username<input class={field} value={userName.split(' ')[0].toLowerCase()} onchange={() => (dirty = true)} /></label>
              <label class="flex flex-col gap-2 text-sm">E-mail<input class={field} type="email" value={email} onchange={() => (dirty = true)} /></label>
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-sm">Senha</p>
                  <p class="text-xs text-muted">alterada há 4 meses</p>
                </div>
                <button type="button" class="h-10 rounded-field border border-field-line px-3 text-sm hover:bg-line/40">Trocar senha</button>
              </div>
            </div>
          {:else if section === 'trash'}
            <h3 class="font-serif text-2xl">Lixeira</h3>
            <p class="mb-5 font-mono text-xs text-muted">{summary.trashed} {summary.trashed === 1 ? 'página' : 'páginas'}</p>
            <p class="text-sm leading-relaxed text-muted">
              Páginas excluídas são mantidas por {settings.retention} dias e depois removidas do disco definitivamente. Entradas do Cofre são apagadas na hora, sem passar pela lixeira.
            </p>
            <button type="button" class="mt-5 h-10 rounded-field border border-field-line px-3 text-sm hover:bg-line/40 disabled:opacity-50" disabled={summary.trashed === 0} onclick={onemptytrash}>
              Esvaziar lixeira agora
            </button>
          {:else if section === 'data'}
            <h3 class="font-serif text-2xl">Importar / exportar</h3>
            <p class="mb-5 font-mono text-xs text-muted">{summary.pages} páginas · {summary.shared} compartilhadas · {summary.vault} no cofre</p>
            <div class="flex flex-col gap-6">
              <div>
                <p class="mb-2 text-sm">Exportar tudo</p>
                <div class="flex flex-wrap gap-2">
                  <button type="button" class="h-10 rounded-field border border-field-line px-3 text-sm hover:bg-line/40" onclick={() => onexport('md')}>Markdown</button>
                  <button type="button" class="h-10 rounded-field border border-field-line px-3 text-sm hover:bg-line/40" onclick={() => onexport('json')}>JSON</button>
                </div>
                <p class="mt-2 font-mono text-xs text-muted">o cofre fica de fora: só sai cifrado</p>
              </div>
              <div>
                <p class="mb-2 text-sm">Importar</p>
                <label class="flex cursor-pointer flex-col items-center gap-2 rounded-field border border-dashed border-field-line p-6 text-center hover:bg-line/30 focus-within:outline-2">
                  <Icon name="upload" size={22} />
                  <span class="text-sm">Arraste arquivos aqui ou clique para escolher</span>
                  <span class="font-mono text-xs text-muted">.md · .txt</span>
                  <input type="file" multiple accept=".md,.txt,text/markdown,text/plain" class="sr-only" aria-label="Escolher arquivos para importar" onchange={picked} />
                </label>
              </div>
            </div>
          {:else}
            <h3 class="font-serif text-2xl">IA (opcional)</h3>
            <p class="mb-5 font-mono text-xs text-muted">desligada por padrão</p>
            <div class="flex flex-col gap-5">
              <label class="flex flex-col gap-2 text-sm">
                Provedor
                <select class={field} bind:value={providerId} onchange={() => (dirty = true)}>
                  {#each AI_PROVIDERS as p (p.id)}
                    <option value={p.id}>{p.label}</option>
                  {/each}
                </select>
              </label>
              <label class="flex flex-col gap-2 text-sm">
                {provider.local ? 'Endereço do servidor' : 'Chave de API'}
                {#key provider.id}
                  <input class={field} type={provider.local ? 'url' : 'password'} autocomplete="off" placeholder={provider.placeholder} onchange={() => (dirty = true)} />
                {/key}
              </label>
              <p class="flex items-start gap-2 text-xs text-muted">
                <Icon name="lock" size={14} />
                <span>A chave será guardada cifrada no cofre desta instância e nunca aparecerá em logs ou exportações. Neste protótipo ela ainda não é salva.</span>
              </p>
            </div>
          {/if}
        </div>
      {/if}
    </div>

    <div class="flex items-center gap-3 border-t border-line px-4 py-3 {stacked && atList ? 'hidden' : ''}">
      <span class="mr-auto font-mono text-xs {dirty ? 'text-offline-text' : 'text-muted'}" role="status">{dirty ? 'alterações não salvas' : 'tudo salvo'}</span>
      <button type="button" class="h-10 rounded-field border border-field-line px-4 text-sm hover:bg-line/40" onclick={onclose}>Fechar</button>
      {#if dirty}
        <button type="button" class="h-10 rounded-field bg-cream px-4 text-sm font-semibold text-on-cream hover:bg-cream/90" onclick={save}>Salvar</button>
      {/if}
    </div>
  </div>
</div>
