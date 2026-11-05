<script lang="ts">
  import { fade, fly } from 'svelte/transition'
  import { modal } from '../../a11y/dialog'
  import { ms } from '../../motion'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { describePerms, type PermKey } from '../../stores/permissions'
  import { toast } from '../../stores/toast.svelte'
  import { ME, initialsOf, searchUsers } from '../../stores/users'
  import Icon from '../dashboard/Icon.svelte'
  import PermissionPicker from './PermissionPicker.svelte'

  interface Props {
    ed: PageEditor
    /** Which side opens first: the people who have access, or the list to add from. */
    tab?: 'access' | 'add'
    onclose: () => void
  }

  let { ed, tab = $bindable('access'), onclose }: Props = $props()

  const opener = document.activeElement
  let query = $state('')
  let picked = $state<string[]>([])
  // new people start with the least access: reading
  let newPerms = $state<PermKey[]>([])
  let editing = $state<string | null>(null)
  let confirmAll = $state(false)

  const ws = $derived(ed.ws)
  const owner = $derived(ed.isOwner)
  const shares = $derived(ed.shares)
  const candidates = $derived(searchUsers(ws.users, query).filter((u) => u.id !== ME && !shares.some((s) => s.userId === u.id)))
  const available = $derived(ws.users.filter((u) => u.id !== ME && !shares.some((s) => s.userId === u.id)).length)

  function toggle(id: string, on: boolean) {
    picked = on ? [...new Set([...picked, id])] : picked.filter((x) => x !== id)
  }

  function submit(e: SubmitEvent) {
    e.preventDefault()
    const added = ed.share(picked, newPerms)
    if (!added) return
    toast.show(`Compartilhada com ${added} ${added === 1 ? 'pessoa' : 'pessoas'}`)
    picked = []
    query = ''
    tab = 'access'
  }

  function removeAll() {
    if (!confirmAll) {
      confirmAll = true
      return
    }
    ed.unshareAll()
    confirmAll = false
    toast.show('Compartilhamento retirado de todos')
  }

  function remove(userId: string) {
    const name = ws.user(userId)?.name ?? 'pessoa'
    ed.unshare(userId)
    if (editing === userId) editing = null
    toast.show(`Acesso de ${name} retirado`)
  }

  function focusOnMount(node: HTMLElement) {
    node.focus()
  }
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && onclose()} />

<div class="fixed inset-0 z-[70] flex items-end justify-center sm:items-center sm:p-6" transition:fade|global={{ duration: ms(200) }}>
  <button type="button" tabindex="-1" aria-hidden="true" data-testid="share-backdrop" class="absolute inset-0 cursor-default bg-black/60" onclick={onclose}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-labelledby="share-title"
    use:modal={opener}
    transition:fly|global={{ y: 40, duration: ms(220) }}
    class="relative flex max-h-[92dvh] w-full max-w-xl flex-col overflow-hidden rounded-t-3xl border border-line bg-surface sm:rounded-3xl"
  >
    <div class="flex items-start gap-3 px-6 pt-5">
      <div class="min-w-0 flex-1">
        <h2 id="share-title" class="font-serif text-2xl">Compartilhar</h2>
        <p class="truncate font-mono text-xs text-muted">{ed.page?.title}</p>
      </div>
      <button type="button" class="grid size-9 place-items-center rounded-field text-muted hover:bg-line/50" aria-label="Fechar" onclick={onclose}><Icon name="close" /></button>
    </div>

    <div role="tablist" aria-label="Compartilhamento" class="mt-3 flex gap-1 border-b border-line px-5">
      <button type="button" role="tab" id="tab-access" aria-selected={tab === 'access'} aria-controls="panel-access" class="-mb-px border-b-2 px-3 py-2 text-sm {tab === 'access' ? 'border-accent-line text-fg' : 'border-transparent text-muted hover:text-fg'}" onclick={() => (tab = 'access')}>
        Com acesso <span class="font-mono text-xs">{shares.length}</span>
      </button>
      {#if ed.can('share')}
        <button type="button" role="tab" id="tab-add" aria-selected={tab === 'add'} aria-controls="panel-add" class="-mb-px border-b-2 px-3 py-2 text-sm {tab === 'add' ? 'border-accent-line text-fg' : 'border-transparent text-muted hover:text-fg'}" onclick={() => (tab = 'add')}>
          Adicionar pessoas
        </button>
      {/if}
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto px-6 py-5">
      {#if tab === 'access'}
        <div role="tabpanel" id="panel-access" aria-labelledby="tab-access">
          {#if shares.length === 0}
            <div class="flex flex-col items-center gap-2 rounded-field border border-dashed border-line p-8 text-center" data-testid="no-shares">
              <span class="text-muted"><Icon name="people" size={28} /></span>
              <p class="font-serif text-xl">Ninguém tem acesso ainda</p>
              <p class="text-sm text-muted">Só você vê esta página.</p>
              {#if ed.can('share')}
                <button type="button" class="mt-2 h-10 rounded-field bg-cream px-4 text-sm font-medium text-on-cream" onclick={() => (tab = 'add')}>Adicionar pessoas</button>
              {/if}
            </div>
          {:else}
            <ul class="flex flex-col gap-2">
              {#each shares as share (share.userId)}
                {@const user = ws.user(share.userId)}
                <li class="rounded-field border border-line">
                  <div class="flex items-center gap-3 px-3 py-2.5">
                    <span class="grid size-9 shrink-0 place-items-center rounded-full bg-accent font-mono text-xs" aria-hidden="true">{initialsOf(user?.name ?? '?')}</span>
                    <div class="min-w-0 flex-1">
                      <p class="truncate text-sm font-medium">{user?.name ?? 'Usuário removido'}</p>
                      <p class="truncate font-mono text-xs text-muted">@{user?.username} · {user?.email}</p>
                    </div>
                    <span class="hidden font-mono text-xs text-muted sm:block">{describePerms(share.perms)}</span>
                    {#if owner}
                      <button type="button" class="h-8 rounded-field border border-field-line px-2.5 text-xs hover:bg-line/40" aria-expanded={editing === share.userId} aria-label="Permissões de {user?.name}" onclick={() => (editing = editing === share.userId ? null : share.userId)}>Permissões</button>
                      <button type="button" class="h-8 rounded-field border border-offline px-2.5 text-xs text-offline-text hover:bg-offline/10" aria-label="Retirar acesso de {user?.name}" onclick={() => remove(share.userId)}>Retirar</button>
                    {/if}
                  </div>
                  {#if editing === share.userId}
                    <div class="border-t border-line p-3">
                      <PermissionPicker name="perm-{share.userId}" perms={share.perms} onchange={(p) => ed.setShare(share.userId, p)} />
                    </div>
                  {/if}
                </li>
              {/each}
            </ul>
            {#if owner}
              <div class="mt-4 flex items-center justify-between gap-3">
                <p class="text-xs text-muted">{shares.length} {shares.length === 1 ? 'pessoa' : 'pessoas'} com acesso</p>
                <div class="flex gap-2">
                  {#if confirmAll}<button type="button" class="h-9 rounded-field border border-field-line px-3 text-xs hover:bg-line/40" onclick={() => (confirmAll = false)}>Cancelar</button>{/if}
                  <button type="button" class="h-9 rounded-field border border-offline px-3 text-xs text-offline-text hover:bg-offline/10" onclick={removeAll}>
                    {confirmAll ? `Confirmar: retirar de ${shares.length === 1 ? 'todos (1)' : `todos (${shares.length})`}` : 'Retirar de todos'}
                  </button>
                </div>
              </div>
            {:else}
              <p class="mt-4 text-xs text-muted">Só quem criou a página pode retirar o acesso de alguém.</p>
            {/if}
          {/if}
        </div>
      {:else}
        <div role="tabpanel" id="panel-add" aria-labelledby="tab-add">
        <form class="flex flex-col gap-4" onsubmit={submit}>
          <label class="relative block">
            <span class="sr-only">Buscar por e-mail ou username</span>
            <span class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted"><Icon name="search" size={16} /></span>
            <input use:focusOnMount bind:value={query} type="search" maxlength="120" placeholder="Buscar por e-mail ou username" class="h-11 w-full rounded-field border border-field-line bg-bg pr-3 pl-9 text-sm placeholder:text-muted" />
          </label>

          <div>
            <p class="mb-1.5 font-mono text-[10.5px] tracking-[0.14em] text-muted uppercase" role="status">
              {query.trim() ? `${candidates.length} ${candidates.length === 1 ? 'resultado' : 'resultados'}` : `${available} usuários do servidor`}
            </p>
            {#if candidates.length === 0}
              <p class="rounded-field border border-dashed border-line p-5 text-center text-sm text-muted" data-testid="no-users">
                {available === 0 ? 'Todos os usuários do servidor já têm acesso.' : 'Nenhum usuário encontrado com esse e-mail ou username.'}
              </p>
            {:else}
              <ul class="max-h-56 overflow-y-auto rounded-field border border-line" aria-label="Usuários do servidor">
                {#each candidates as user (user.id)}
                  <li class="border-b border-line last:border-b-0">
                    <label class="flex cursor-pointer items-center gap-3 px-3 py-2 hover:bg-line/30">
                      <input type="checkbox" class="accent-accent-line" checked={picked.includes(user.id)} onchange={(e) => toggle(user.id, e.currentTarget.checked)} aria-label="Selecionar {user.name}" />
                      <span class="grid size-8 shrink-0 place-items-center rounded-full bg-accent font-mono text-[11px]" aria-hidden="true">{initialsOf(user.name)}</span>
                      <span class="min-w-0 flex-1">
                        <span class="block truncate text-sm">{user.name}</span>
                        <span class="block truncate font-mono text-xs text-muted">@{user.username} · {user.email}</span>
                      </span>
                    </label>
                  </li>
                {/each}
              </ul>
            {/if}
          </div>

          <PermissionPicker name="perm-new" perms={newPerms} onchange={(p) => (newPerms = p)} />

          <button type="submit" disabled={picked.length === 0} class="h-11 rounded-field bg-cream px-4 text-sm font-semibold text-on-cream hover:bg-cream/90 disabled:opacity-40">
            {picked.length === 0 ? 'Escolha quem recebe' : `Compartilhar com ${picked.length} ${picked.length === 1 ? 'pessoa' : 'pessoas'}`}
          </button>
        </form>
        </div>
      {/if}
    </div>
  </div>
</div>
