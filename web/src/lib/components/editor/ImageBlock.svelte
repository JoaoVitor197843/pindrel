<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { toast } from '../../stores/toast.svelte'
  import Icon from '../dashboard/Icon.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'image' }>
  }

  let { ed, block }: Props = $props()

  const TYPES = ['image/png', 'image/jpeg', 'image/webp', 'image/gif']
  const MAX_BYTES = 8_000_000
  let over = $state(false)

  function take(file: File | undefined) {
    if (!file) return
    if (!TYPES.includes(file.type)) return void toast.show('Use uma imagem PNG, JPEG, WebP ou GIF')
    if (file.size > MAX_BYTES) return void toast.show('A imagem passa de 8 MB')
    ed.setImage(block.id, file.name, URL.createObjectURL(file))
  }
</script>

{#if block.src}
  <figure class="flex flex-col gap-2">
    <img src={block.src} alt={block.name ?? 'Imagem'} class="max-h-[28rem] max-w-full rounded-field border border-line object-contain" />
    <figcaption class="flex items-center gap-3 font-mono text-xs text-muted">
      <span class="truncate">{block.name}</span>
      {#if ed.can('images')}
        <button type="button" class="underline hover:text-fg" onclick={() => ed.setImage(block.id, null, null)}>remover</button>
      {/if}
    </figcaption>
  </figure>
{:else if ed.can('images')}
  <label
    class="flex cursor-pointer flex-col items-center gap-2 rounded-field border border-dashed p-8 text-center text-muted hover:bg-line/30 focus-within:outline-2 {over ? 'border-accent-line bg-line/30' : 'border-field-line'}"
    ondragover={(e) => {
      e.preventDefault()
      over = true
    }}
    ondragleave={() => (over = false)}
    ondrop={(e) => {
      e.preventDefault()
      over = false
      take(e.dataTransfer?.files?.[0])
    }}
  >
    <Icon name="upload" size={22} />
    <span class="text-sm">Arraste uma imagem aqui ou clique para escolher</span>
    <span class="font-mono text-xs">PNG · JPEG · WebP · GIF, até 8 MB</span>
    <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" class="sr-only" aria-label="Escolher imagem" onchange={(e) => (take(e.currentTarget.files?.[0]), (e.currentTarget.value = ''))} />
  </label>
{:else}
  <p class="font-mono text-xs text-muted">imagem vazia</p>
{/if}
