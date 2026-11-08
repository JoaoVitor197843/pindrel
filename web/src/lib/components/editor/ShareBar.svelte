<script lang="ts">
  import type { PageEditor } from '../../stores/editor.svelte'
  import { describePerms } from '../../stores/permissions'
  import { initialsOf } from '../../stores/users'
  import Icon from '../dashboard/Icon.svelte'

  interface Props {
    ed: PageEditor
    /** Opens the sharing modal on one side or the other. */
    onopen: (tab: 'access' | 'add') => void
  }

  let { ed, onopen }: Props = $props()

  const page = $derived(ed.page)
  const shown = $derived(ed.shares.slice(0, 4))
  const extra = $derived(Math.max(0, ed.shares.length - shown.length))
</script>

<div class="flex flex-wrap items-center gap-x-3 gap-y-2 text-sm" role="group" aria-label="Compartilhamento">
  <span class="text-muted"><Icon name="people" size={16} /></span>
  {#if page?.sharedBy}
    <span>Compartilhada por <strong class="font-medium">{page.sharedBy}</strong></span>
    <span class="font-mono text-xs text-muted">você pode: {describePerms(page.myPerms).toLowerCase()}</span>
  {:else if ed.shares.length}
    <span class="text-muted">Compartilhada com</span>
    <ul class="flex flex-wrap items-center gap-1.5" aria-label="Pessoas com acesso">
      {#each shown as share (share.userId)}
        {@const user = ed.ws.user(share.userId)}
        <li class="inline-flex items-center gap-1.5 rounded-full border border-line py-0.5 pr-2.5 pl-0.5" title="{user?.name} — {describePerms(share.perms)}">
          <span class="grid size-6 place-items-center rounded-full bg-accent font-mono text-[10px]" aria-hidden="true">{initialsOf(user?.name ?? '?')}</span>
          <span class="text-xs">{user?.name.split(' ')[0] ?? 'Removido'}</span>
          <span class="sr-only">{describePerms(share.perms)}</span>
        </li>
      {/each}
      {#if extra}<li class="font-mono text-xs text-muted">+{extra}</li>{/if}
    </ul>
  {:else}
    <span class="text-muted">Não compartilhada</span>
  {/if}

  {#if ed.can('share')}
    <button type="button" class="inline-flex h-8 items-center gap-1.5 rounded-full border border-dashed border-field-line px-3 text-xs hover:bg-line/40" onclick={() => onopen('add')}>
      <Icon name="plus" size={12} />Compartilhar
    </button>
  {/if}
  {#if ed.isOwner && ed.shares.length}
    <button type="button" class="inline-flex h-8 items-center rounded-full border border-field-line px-3 text-xs text-muted hover:bg-line/40 hover:text-fg" onclick={() => onopen('access')}>Retirar acesso…</button>
  {/if}

</div>
