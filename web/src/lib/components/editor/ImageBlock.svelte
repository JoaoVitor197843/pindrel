<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { toast } from '../../stores/toast.svelte'
  import Icon from '../dashboard/Icon.svelte'
  import { fileLink } from './fileLink.svelte'
  import UploadPicker from './UploadPicker.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'image' }>
  }

  let { ed, block }: Props = $props()

  const TYPES = ['image/png', 'image/jpeg', 'image/webp', 'image/gif']
  // without a server the picture only lives in this session, so it stays small; with one the limit is the server's
  const MAX_BYTES = 8_000_000
  let over = $state(false)
  let retried = $state(false)

  const link = fileLink(() => ed, () => block.fileId)
  const shown = $derived(block.fileId ? link.url : block.src)

  function take(file: File | undefined) {
    if (!file) return
    if (!TYPES.includes(file.type)) return void toast.show('Use uma imagem PNG, JPEG, WebP ou GIF')
    if (file.size > MAX_BYTES) return void toast.show('A imagem passa de 8 MB')
    ed.setImage(block.id, file.name, URL.createObjectURL(file))
  }

  // the address of a picture on the server stops working after a while: one new try, then the error
  async function failed() {
    if (!block.fileId || retried) return
    retried = true
    await link.refresh()
  }
</script>

{#if block.fileId || block.src}
  <figure class="flex flex-col gap-2">
    {#if shown}
      <img src={shown} alt={block.name ?? 'Imagem'} class="max-h-[28rem] max-w-full rounded-field border border-line object-contain" onerror={failed} />
    {:else if link.error}
      <p class="rounded-field border border-line px-4 py-6 text-sm text-muted">{link.error}</p>
    {:else}
      <div class="h-40 animate-pulse rounded-field border border-line bg-line/30 motion-reduce:animate-none" aria-label="Carregando imagem" role="img"></div>
    {/if}
    <figcaption class="flex items-center gap-3 font-mono text-xs text-muted">
      <span class="truncate">{block.name}</span>
      {#if ed.can('images')}
        <button type="button" class="underline hover:text-fg" onclick={() => ed.setImage(block.id, null, null)}>remover</button>
      {/if}
    </figcaption>
  </figure>
{:else if ed.can('images') && ed.files.available}
  <UploadPicker {ed} blockId={block.id} label="Arraste uma imagem aqui ou clique para escolher" hint="PNG · JPEG · WebP · GIF" accept="image/png,image/jpeg,image/webp,image/gif" />
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
