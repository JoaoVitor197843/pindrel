<script lang="ts">
  import type { PageEditor } from '../../stores/editor.svelte'
  import { TAG_COLORS } from '../../stores/workspace.svelte'
  import Icon from '../dashboard/Icon.svelte'
  import { COLOR_LABEL, TAG_STYLE } from '../dashboard/tags'
  import { place } from './autosize'

  interface Props {
    ed: PageEditor
  }

  let { ed }: Props = $props()

  let adding = $state(false)
  let draft = $state('')
  let color = $state<(typeof TAG_COLORS)[number]>('accent')

  const page = $derived(ed.page)
  const mine = $derived((page?.tags ?? []).map((id) => ed.ws.tag(id)).filter((t) => !!t))
  const available = $derived(ed.ws.tags.filter((t) => !page?.tags.includes(t.id)))

  function submit(e: SubmitEvent) {
    e.preventDefault()
    if (ed.addTag(draft, color)) {
      draft = ''
      adding = false
    } else if (!draft.trim()) adding = false
    else draft = ''
  }

  function focusOnMount(node: HTMLInputElement) {
    place(node)
  }
</script>

<div class="flex flex-wrap items-center gap-2" role="group" aria-label="Tags da página">
  {#each mine as tag (tag.id)}
    <span class="inline-flex items-center gap-1.5 rounded-full py-1 pr-1.5 pl-2.5 font-mono text-xs {TAG_STYLE[tag.color].chip}">
      <span class="size-1.5 rounded-full {TAG_STYLE[tag.color].dot}"></span>#{tag.name}
      {#if ed.can('tags')}
        <button type="button" class="grid size-4 place-items-center rounded-full hover:bg-bg/40" aria-label="Remover tag {tag.name}" onclick={() => ed.removeTag(tag.id)}>
          <Icon name="close" size={10} />
        </button>
      {/if}
    </span>
  {/each}
  {#if ed.can('tags')}
    <button
      type="button"
      class="rounded-full border border-dashed border-field-line px-2.5 py-1 font-mono text-xs text-muted hover:text-fg"
      aria-expanded={adding}
      onclick={() => (adding = !adding)}
    >
      + tag
    </button>
  {/if}
</div>

{#if adding}
  <form class="mt-3 flex max-w-md flex-col gap-3 rounded-field border border-line bg-surface p-3" onsubmit={submit}>
    {#if available.length}
      <div class="flex flex-wrap gap-2" role="group" aria-label="Tags que já existem">
        {#each available as tag (tag.id)}
          <button type="button" class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 font-mono text-xs {TAG_STYLE[tag.color].chip}" onclick={() => ed.addTag(tag.name, tag.color)}>
            <span class="size-1.5 rounded-full {TAG_STYLE[tag.color].dot}"></span>{tag.name}
          </button>
        {/each}
      </div>
    {/if}
    <input
      use:focusOnMount
      bind:value={draft}
      maxlength="24"
      aria-label="Nome da nova tag"
      placeholder="nova tag"
      onkeydown={(e) => e.key === 'Escape' && (e.stopPropagation(), (adding = false))}
      class="h-9 rounded-field border border-field-line bg-bg px-3 text-sm placeholder:text-muted"
    />
    <div class="flex items-center gap-2" role="group" aria-label="Cor da tag">
      {#each TAG_COLORS as c (c)}
        <button
          type="button"
          class="size-6 rounded-full border-2 {TAG_STYLE[c].swatch} {color === c ? 'border-fg' : 'border-transparent'}"
          aria-label="Cor {COLOR_LABEL[c]}"
          aria-pressed={color === c}
          onclick={() => (color = c)}
        ></button>
      {/each}
      <button type="submit" class="ml-auto h-8 rounded-field bg-accent px-3 text-xs hover:bg-accent/85">Criar</button>
    </div>
  </form>
{/if}
