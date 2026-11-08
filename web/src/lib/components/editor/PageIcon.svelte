<script lang="ts">
  import { EMOJI_GROUPS, firstEmoji } from '../../stores/emoji'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { prefs } from '../../stores/prefs.svelte'

  interface Props {
    ed: PageEditor
  }

  let { ed }: Props = $props()

  let picking = $state(false)
  let group = $state(EMOJI_GROUPS[0].key)
  let typed = $state('')
  const page = $derived(ed.page)
  const editable = $derived(ed.can('text'))
  const list = $derived(EMOJI_GROUPS.find((g) => g.key === group)?.list ?? [])
  // with a cover the icon straddles its lower edge, like a badge on the border
  const straddle = $derived(!!page?.cover && !!page.icon)

  function choose(icon: string) {
    ed.setIcon(icon)
    if (icon) prefs.rememberIcon(icon)
    picking = false
    typed = ''
  }

  function paste(e: SubmitEvent) {
    e.preventDefault()
    const found = firstEmoji(typed)
    if (found) choose(found)
    else typed = ''
  }
</script>

<svelte:window onmousedown={(e) => picking && !(e.target as Element).closest?.('[data-icon-menu]') && (picking = false)} />

{#if page && (page.icon || (editable && (!page.cover || !page.icon)))}
  <div
    class="pointer-events-none relative z-10 mb-3 flex flex-wrap items-end gap-2 {straddle ? '-mt-20 md:-mt-[5.5rem]' : page.cover ? 'mt-5' : ''} {straddle && prefs.iconAlign === 'center' ? 'justify-center' : ''}"
    data-icon-menu
    data-testid="icon-row"
  >
    {#if page.icon}
      {#key page.icon}
        {#if editable}
          <button
            type="button"
            class="animate-icon pointer-events-auto grid size-20 place-items-center rounded-field text-6xl leading-none hover:bg-line/40 md:size-24 md:text-7xl"
            aria-label="Trocar ícone da página"
            aria-haspopup="dialog"
            aria-expanded={picking}
            onclick={() => (picking = !picking)}
          >
            <span aria-hidden="true">{page.icon}</span>
          </button>
        {:else}
          <span class="animate-icon pointer-events-auto grid size-20 place-items-center text-6xl leading-none md:size-24 md:text-7xl" role="img" aria-label="Ícone da página">{page.icon}</span>
        {/if}
      {/key}
    {/if}
    {#if editable}
      {#if !page.icon}
        <button type="button" class="pointer-events-auto h-8 rounded-field px-2.5 text-xs text-muted hover:bg-line/40 hover:text-fg" aria-haspopup="dialog" aria-expanded={picking} onclick={() => (picking = !picking)}>
          ☺ Adicionar ícone
        </button>
      {/if}
      {#if !page.cover}
        <button type="button" class="pointer-events-auto h-8 rounded-field px-2.5 text-xs text-muted hover:bg-line/40 hover:text-fg" onclick={() => ed.setCover('musgo')}>▭ Adicionar capa</button>
      {/if}
    {/if}

    {#if picking}
      <div
        role="dialog"
        aria-label="Escolher ícone"
        tabindex="-1"
        class="animate-pop pointer-events-auto absolute top-full {straddle && prefs.iconAlign === 'center' ? 'left-1/2 -translate-x-1/2' : 'left-0'} z-30 mt-1 w-80 max-w-[90vw] rounded-field border border-line bg-surface p-2.5 shadow-xl"
        onkeydown={(e) => e.key === 'Escape' && (e.stopPropagation(), (picking = false))}
      >
        {#if prefs.recentIcons.length}
          <div class="mb-2 flex flex-wrap items-center gap-1" role="group" aria-label="Usados há pouco">
            <span class="mr-1 font-mono text-[10px] tracking-[0.14em] text-muted uppercase">recentes</span>
            {#each prefs.recentIcons as icon (icon)}
              <button type="button" class="grid size-8 place-items-center rounded text-xl hover:bg-line/50" aria-label="Recente {icon}" onclick={() => choose(icon)}>{icon}</button>
            {/each}
          </div>
        {/if}
        <div class="mb-2 flex gap-0.5 border-b border-line pb-1.5" role="tablist" aria-label="Tipos de ícone">
          {#each EMOJI_GROUPS as g (g.key)}
            <button
              type="button"
              role="tab"
              class="grid size-8 flex-1 place-items-center rounded text-lg {group === g.key ? 'bg-line/60' : 'opacity-60 hover:bg-line/40 hover:opacity-100'}"
              aria-selected={group === g.key}
              aria-label={g.label}
              title={g.label}
              onclick={() => (group = g.key)}
            >
              {g.sign}
            </button>
          {/each}
        </div>
        <div class="grid max-h-56 grid-cols-8 gap-0.5 overflow-y-auto" role="tabpanel" aria-label="Ícones de {EMOJI_GROUPS.find((g) => g.key === group)?.label}">
          {#each list as icon (icon)}
            <button
              type="button"
              class="grid h-9 w-full place-items-center rounded text-xl hover:bg-line/50 {page.icon === icon ? 'bg-line/50' : ''}"
              aria-label="Ícone {icon}"
              aria-pressed={page.icon === icon}
              onclick={() => choose(icon)}
            >
              {icon}
            </button>
          {/each}
        </div>
        <form class="mt-2 flex gap-1.5" onsubmit={paste}>
          <input bind:value={typed} maxlength="40" aria-label="Colar qualquer emoji" placeholder="Cole qualquer emoji" class="h-8 min-w-0 flex-1 rounded-field border border-field-line bg-bg px-2.5 text-sm placeholder:text-muted" />
          <button type="submit" class="h-8 rounded-field bg-accent px-3 text-xs hover:bg-accent/85">Usar</button>
        </form>
        {#if page.icon}
          <button type="button" class="mt-2 h-8 w-full rounded-field border border-field-line text-xs text-muted hover:bg-line/40 hover:text-fg" onclick={() => choose('')}>Remover ícone</button>
        {/if}
      </div>
    {/if}
  </div>
{/if}
