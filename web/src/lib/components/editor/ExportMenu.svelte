<script lang="ts">
  import type { PageEditor } from '../../stores/editor.svelte'
  import { toast } from '../../stores/toast.svelte'
  import { FORMATS, download, exportPage, fileNameFor, type ExportFormat } from '../../stores/transfer'
  import Icon from '../dashboard/Icon.svelte'

  interface Props {
    ed: PageEditor
  }

  let { ed }: Props = $props()

  let open = $state(false)
  let includeSecure = $state(false)
  let root: HTMLElement | undefined = $state()

  const secureCount = $derived(ed.blocks.filter((b) => b.type === 'secure').length)
  // a secret leaves the app only when the person may see it and the vault is open right now
  const mayIncludeSecure = $derived(secureCount > 0 && ed.can('secure') && ed.ws.vaultUnlocked)
  const options = $derived({ includeSecure: includeSecure && mayIncludeSecure })

  function save(format: ExportFormat) {
    const p = ed.page
    if (!p) return
    const f = FORMATS[format]
    const ok = download(fileNameFor(p.title, f.ext), exportPage(p, ed.ws.tags, format, options), f.mime)
    toast.show(ok ? `Exportada como ${f.label}` : 'Não foi possível exportar')
    open = false
  }

  async function copy() {
    const p = ed.page
    if (!p) return
    try {
      await navigator.clipboard.writeText(exportPage(p, ed.ws.tags, 'md', options))
      toast.show('Markdown copiado')
    } catch {
      toast.show('Não foi possível copiar')
    }
    open = false
  }
</script>

<svelte:window
  onkeydown={(e) => e.key === 'Escape' && open && (open = false)}
  onmousedown={(e) => open && root && !root.contains(e.target as Node) && (open = false)}
/>

<div class="relative" bind:this={root}>
  <button
    type="button"
    class="inline-flex h-10 items-center gap-2 rounded-field px-2.5 text-sm text-muted hover:bg-line/40 hover:text-fg md:border md:border-line md:px-3"
    aria-haspopup="menu"
    aria-expanded={open}
    aria-label="Exportar página"
    onclick={() => (open = !open)}
  >
    <Icon name="download" size={16} /><span class="hidden md:inline">Exportar</span>
  </button>
  {#if open}
    <div role="menu" aria-label="Exportar página" class="absolute right-0 z-30 mt-2 w-64 rounded-field border border-line bg-surface p-1.5 shadow-xl">
      {#each Object.entries(FORMATS) as [key, f] (key)}
        <button type="button" role="menuitem" class="flex w-full items-center justify-between rounded-[7px] px-2.5 py-2 text-left text-sm hover:bg-line/50" onclick={() => save(key as ExportFormat)}>
          {f.label}<span class="font-mono text-xs text-muted">.{f.ext}</span>
        </button>
      {/each}
      <button type="button" role="menuitem" class="w-full rounded-[7px] px-2.5 py-2 text-left text-sm hover:bg-line/50" onclick={copy}>Copiar como Markdown</button>
      {#if secureCount > 0}
        <div class="mt-1 border-t border-line px-2.5 pt-2 pb-1">
          {#if mayIncludeSecure}
            <label class="flex cursor-pointer items-center gap-2 text-xs">
              <input type="checkbox" class="accent-accent-line" bind:checked={includeSecure} />
              Incluir {secureCount === 1 ? 'o bloco seguro' : `os ${secureCount} blocos seguros`}
            </label>
          {:else}
            <p class="text-xs text-muted">{secureCount === 1 ? '1 bloco seguro fica' : `${secureCount} blocos seguros ficam`} de fora. Desbloqueie o cofre para incluir.</p>
          {/if}
        </div>
      {/if}
    </div>
  {/if}
</div>
