<script lang="ts">
  import { selection } from '../../stores/servers.svelte'

  // The six numbers of a device that is pairing with this server, for the person who is already using the web (a device that
  // trusts the server is sent past the connection page, so it cannot show them). Asked for only while this is open.
  let open = $state(false)
  let digits = $state('')
  let left = $state(0)
  let from = $state('')
  let problem = $state(false)

  const SHAPE = /^\d{6}$/

  function read(text: string) {
    const v: Record<string, string> = {}
    for (const line of text.split('\n')) {
      const i = line.indexOf('=')
      if (i > 0) v[line.slice(0, i)] = line.slice(i + 1).trim()
    }
    if (!SHAPE.test(v.sas ?? '')) return false
    digits = v.sas
    left = Math.max(0, Math.min(60, parseInt(v.left, 10) || 0))
    from = (v.from ?? '').replace(/[^0-9a-f:.]/gi, '').slice(0, 45)
    return true
  }

  $effect(() => {
    if (!open) return
    let busy = false
    let ctl: AbortController | undefined
    const tick = async () => {
      if (busy || document.hidden) return
      busy = true
      ctl = new AbortController()
      const timer = setTimeout(() => ctl?.abort(), 3000)
      try {
        const r = await fetch('/server/pair/sas', { cache: 'no-store', signal: ctl.signal })
        problem = false
        if (r.status === 200 && read(await r.text())) return
        digits = ''
        problem = r.status !== 200 && r.status !== 204
      } catch {
        digits = ''
        problem = true
      } finally {
        clearTimeout(timer)
        busy = false
      }
    }
    void tick()
    const id = setInterval(tick, 2000)
    return () => {
      clearInterval(id)
      ctl?.abort()
    }
  })
</script>

{#if selection.tlsOffered}
  <details
    class="mx-auto mt-3 max-w-[480px] rounded-[10px] border border-line px-4 py-2 text-center"
    ontoggle={(e) => (open = e.currentTarget.open)}
    data-testid="pairing-code"
  >
    <summary class="cursor-pointer font-mono text-[11px] tracking-[0.6px] text-accent-text select-none">Parear um aparelho</summary>
    <div class="pt-3 pb-1" aria-live="polite">
      {#if digits}
        <p class="text-xs text-muted">Confira com o app (aparelho {from}):</p>
        <p class="my-2 font-mono text-4xl tracking-[0.3em] text-fg" data-testid="pairing-digits" aria-label="Número de conferência: {digits.split('').join(' ')}">
          {digits.slice(0, 3)} {digits.slice(3)}
        </p>
        <p class="text-xs text-muted">Vale por mais {left} s. Se forem diferentes, <strong>não confirme</strong>: toque em Cancelar no app.</p>
      {:else if problem}
        <p class="text-xs text-offline-text">Não foi possível consultar o servidor agora.</p>
      {:else}
        <p class="text-xs text-muted">Nenhum aparelho está pareando agora. Quando você iniciar o pareamento no app, os 6 números aparecem aqui.</p>
      {/if}
    </div>
  </details>
{/if}
