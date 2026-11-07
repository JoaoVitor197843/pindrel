<script lang="ts">
  import { isDirectMedia, type Block } from '../../stores/blocks'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { toast } from '../../stores/toast.svelte'
  import UrlForm from './UrlForm.svelte'

  interface Props {
    ed: PageEditor
    block: Extract<Block, { type: 'video' | 'audio' | 'pdf' }>
  }

  let { ed, block }: Props = $props()

  const NAMES = { video: 'Vídeo', audio: 'Áudio', pdf: 'PDF' } as const
  const name = $derived(NAMES[block.type])
  let editing = $state(false)
  let failed = $state(false)
  const label = $derived(
    block.title ||
      (() => {
        try {
          return decodeURIComponent(new URL(block.url).pathname.split('/').filter(Boolean).pop() ?? '') || new URL(block.url).hostname
        } catch {
          return block.url
        }
      })(),
  )
  // The file stays on its own server. A player only asks for it when the person presses play (preload="none"), and a PDF
  // opens in its own tab: nothing here downloads, decodes or holds a file on its own.
  const playable = $derived(block.type !== 'pdf' && isDirectMedia(block.type, block.url) && !failed)
</script>

{#if (block.url === '' || editing) && ed.can('text')}
  <UrlForm url={block.url} title={block.title} hint="https://… .{block.type === 'video' ? 'mp4' : block.type === 'audio' ? 'mp3' : 'pdf'}" onsave={(u, t) => ed.setUrl(block.id, u, t) && ((editing = false), (failed = false), true)} onerror={(m) => toast.show(m)} />
{:else if block.url}
  <div class="flex flex-col gap-2 rounded-field border border-line p-3">
    {#if playable && block.type === 'video'}
      <!-- svelte-ignore a11y_media_has_caption -->
      <video controls preload="none" playsinline src={block.url} aria-label="{name}: {label}" class="max-h-[70vh] w-full rounded bg-black" onerror={() => (failed = true)}></video>
    {:else if playable && block.type === 'audio'}
      <audio controls preload="none" src={block.url} aria-label="{name}: {label}" class="w-full" onerror={() => (failed = true)}></audio>
    {/if}
    <div class="flex items-center gap-3">
      <span class="grid h-8 min-w-8 shrink-0 place-items-center rounded border border-line px-1 font-mono text-[10px] text-muted" aria-hidden="true">{block.type === 'pdf' ? 'PDF' : block.type === 'video' ? '▶' : '♪'}</span>
      <a href={block.url} target="_blank" rel="noopener noreferrer" class="min-w-0 flex-1" aria-label="Abrir {name.toLowerCase()} {label}">
        <span class="block truncate text-[15px] font-medium">{label}</span>
        <span class="block truncate font-mono text-xs text-muted">
          {#if block.type !== 'pdf' && !playable}{failed ? 'Não foi possível carregar: abra em outra aba' : 'Este endereço não é um arquivo direto: abra em outra aba'}{:else}{block.url}{/if}
        </span>
      </a>
      {#if ed.can('text')}
        <button type="button" class="shrink-0 rounded px-2 py-1 text-sm text-muted hover:bg-line/50 hover:text-fg" onclick={() => (editing = true)}>Editar</button>
      {/if}
    </div>
  </div>
{:else}
  <p class="rounded-field border border-line px-4 py-3 text-sm text-muted">{name} sem endereço</p>
{/if}
