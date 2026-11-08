<script lang="ts">
  import { ALL_PERMS, LEVEL_LABEL, PERMS, describePerms, levelOf, permsFor, type PermKey } from '../../stores/permissions'

  interface Props {
    perms: PermKey[]
    /** Unique per picker on the screen: it names the radio group and the ids. */
    name: string
    onchange: (perms: PermKey[]) => void
  }

  let { perms, name, onchange }: Props = $props()

  const level = $derived(levelOf(perms))

  function toggle(key: PermKey, on: boolean) {
    const set = new Set(perms)
    if (on) set.add(key)
    else set.delete(key)
    onchange(ALL_PERMS.filter((k) => set.has(k)))
  }
</script>

<div class="flex flex-col gap-3">
  <fieldset class="flex flex-col gap-1.5">
    <legend class="mb-1 font-mono text-[10.5px] tracking-[0.14em] text-muted uppercase">Nível de acesso</legend>
    {#each ['edit', 'read'] as const as lv (lv)}
      <label class="flex cursor-pointer items-center gap-2.5 rounded-field px-2 py-1.5 text-sm hover:bg-line/40">
        <input type="radio" {name} value={lv} checked={level === lv} class="accent-accent-line" onchange={() => onchange(permsFor(lv))} />
        {LEVEL_LABEL[lv]}
        <span class="text-xs text-muted">{lv === 'edit' ? '— tudo liberado' : '— só ver e exportar se permitido abaixo'}</span>
      </label>
    {/each}
    {#if level === 'custom'}
      <label class="flex items-center gap-2.5 rounded-field px-2 py-1.5 text-sm">
        <input type="radio" {name} value="custom" checked disabled class="accent-accent-line" />
        {describePerms(perms)}
      </label>
    {/if}
  </fieldset>

  <details open={level === 'custom'} class="rounded-field border border-line">
    <summary class="cursor-pointer px-3 py-2 text-sm select-none">Avançado</summary>
    <ul class="flex flex-col gap-0.5 border-t border-line p-2" aria-label="Permissões">
      {#each PERMS as perm (perm.key)}
        <li>
          <label class="flex cursor-pointer items-start gap-2.5 rounded-field px-2 py-1.5 hover:bg-line/40">
            <input type="checkbox" class="mt-1 accent-accent-line" checked={perms.includes(perm.key)} onchange={(e) => toggle(perm.key, e.currentTarget.checked)} />
            <span class="text-sm">
              {perm.label}
              <span class="block text-xs text-muted">{perm.hint}</span>
            </span>
          </label>
        </li>
      {/each}
    </ul>
  </details>
</div>
