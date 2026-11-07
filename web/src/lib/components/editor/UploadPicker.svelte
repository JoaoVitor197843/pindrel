<script lang="ts">
  import type { PageEditor } from '../../stores/editor.svelte'
  import { formatBytes } from '../../stores/bytes'
  import Icon from '../dashboard/Icon.svelte'

  interface Props {
    ed: PageEditor
    blockId: string
    label: string
    hint: string
    accept?: string
    /** Takes the file when it is picked; true when it was taken. Default: send it into the block. */
    onpick?: (file: File) => boolean | void
  }

  let { ed, blockId, label, hint, accept, onpick }: Props = $props()

  let over = $state(false)
  const up = $derived(ed.uploading[blockId])
  const percent = $derived(up && up.total ? Math.min(100, Math.floor((up.sent / up.total) * 100)) : 0)

  function take(list: FileList | null | undefined) {
    const file = list?.[0]
    if (!file) return
    if (onpick) onpick(file)
    else ed.uploadInto(blockId, file)
  }
</script>

{#if up && up.status !== 'failed' && up.status !== 'cancelled'}
  <div class="flex flex-col gap-2 rounded-field border border-line p-4" data-upload={blockId}>
    <div class="flex items-center justify-between gap-3 text-sm">
      <span class="min-w-0 truncate">{up.name}</span>
      <span class="shrink-0 font-mono text-xs text-muted">{up.status === 'queued' ? 'na fila' : `${formatBytes(up.sent)} de ${formatBytes(up.total)}`}</span>
    </div>
    <div class="h-1.5 overflow-hidden rounded-full bg-line" role="progressbar" aria-label="Enviando {up.name}" aria-valuemin="0" aria-valuemax="100" aria-valuenow={percent}>
      <div class="h-full bg-accent-line transition-[width] duration-200 motion-reduce:transition-none" style:width="{percent}%"></div>
    </div>
    <button type="button" class="self-start rounded px-2 py-1 text-sm text-muted hover:bg-line/50 hover:text-fg" onclick={() => ed.dismissUpload(blockId)}>Cancelar</button>
  </div>
{:else if up}
  <div class="flex flex-col gap-2 rounded-field border border-line p-4" role="alert">
    <p class="text-sm text-offline-text">{up.error || 'O envio foi cancelado'}</p>
    <div class="flex gap-2">
      <button type="button" class="rounded px-2 py-1 text-sm text-muted hover:bg-line/50 hover:text-fg" onclick={() => ed.dismissUpload(blockId)}>Dispensar</button>
    </div>
  </div>
{:else if ed.can('blocks')}
  <label
    class="flex cursor-pointer flex-col items-center gap-2 rounded-field border border-dashed p-8 text-center text-muted focus-within:outline-2 hover:bg-line/30 {over ? 'border-accent-line bg-line/30' : 'border-field-line'}"
    ondragover={(e) => {
      e.preventDefault()
      e.stopPropagation()
      over = true
    }}
    ondragleave={() => (over = false)}
    ondrop={(e) => {
      e.preventDefault()
      e.stopPropagation()
      over = false
      take(e.dataTransfer?.files)
    }}
  >
    <Icon name="upload" size={22} />
    <span class="text-sm">{label}</span>
    <span class="font-mono text-xs">{hint}</span>
    <input type="file" {accept} class="sr-only" aria-label={label} onchange={(e) => (take(e.currentTarget.files), (e.currentTarget.value = ''))} />
  </label>
{:else}
  <p class="font-mono text-xs text-muted">sem arquivo</p>
{/if}
