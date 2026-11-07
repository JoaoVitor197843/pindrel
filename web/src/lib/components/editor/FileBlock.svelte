<script lang="ts">
  import type { Block } from '../../stores/blocks'
  import { formatBytes } from '../../stores/bytes'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { toast } from '../../stores/toast.svelte'
  import { fileLink } from './fileLink.svelte'
  import UploadPicker from './UploadPicker.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'file' }>
  }

  let { ed, block }: Props = $props()

  const link = fileLink(() => ed, () => block.fileId)
  let asking = $state(false)

  // a file of a kind the server does not know (level 3) can be anything: it only downloads, after a warning
  async function download() {
    asking = false
    const url = (await link.refresh()) || link.url
    if (!url) return void toast.show('Não foi possível abrir o arquivo')
    const a = document.createElement('a')
    a.href = url
    a.rel = 'noopener'
    a.click()
  }
</script>

{#if !block.fileId}
  <UploadPicker {ed} blockId={block.id} label="Arraste um arquivo aqui ou clique para escolher" hint={ed.files.available ? 'Qualquer tipo, até o limite deste servidor' : 'Entre em um servidor para enviar arquivos'} />
{:else}
  <div class="flex flex-col gap-2 rounded-field border border-line px-4 py-3">
    <div class="flex items-center gap-3">
      <span class="grid h-8 min-w-8 shrink-0 place-items-center rounded border border-line px-1 text-base" aria-hidden="true">📎</span>
      <div class="min-w-0 flex-1">
        <span class="block truncate text-[15px] font-medium">{block.name || 'Arquivo sem nome'}</span>
        <span class="block truncate font-mono text-xs text-muted">{formatBytes(block.size)}{block.mime && block.mime !== 'application/octet-stream' ? ` · ${block.mime}` : ''}</span>
      </div>
      <button
        type="button"
        class="shrink-0 rounded-field border border-field-line px-3 py-1.5 text-sm hover:bg-line/50 disabled:opacity-50"
        disabled={!ed.files.available}
        aria-label="Baixar {block.name || 'arquivo'}"
        onclick={() => (block.level === 3 ? (asking = true) : download())}
      >
        Baixar
      </button>
    </div>
    {#if asking}
      <div class="flex flex-col gap-2 rounded border border-line bg-surface p-3 text-sm" role="alertdialog" aria-label="Baixar arquivo desconhecido">
        <p>Este é um arquivo de um tipo que o Pindrel não reconhece. Baixe só se você confia em quem o enviou.</p>
        <div class="flex gap-2">
          <button type="button" class="rounded-field bg-cream px-3 py-1.5 font-medium text-on-cream" onclick={download}>Baixar mesmo assim</button>
          <button type="button" class="rounded px-3 py-1.5 text-muted hover:bg-line/50" onclick={() => (asking = false)}>Cancelar</button>
        </div>
      </div>
    {/if}
    {#if link.error}<p class="text-xs text-offline-text">{link.error}</p>{/if}
  </div>
{/if}
