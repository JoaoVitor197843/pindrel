<script lang="ts">
  import { selection } from '../../stores/servers.svelte'

  // The six numbers of a device that is pairing with this server, for the person who is already using the web (a device that
  // trusts the server is sent past the connection page, so it cannot show them). Asked for only while this is open.
  let open = $state(false)
  type Row = { digits: string; left: number; from: string }
  let rows = $state<Row[]>([])
  let problem = $state(false)

  // one line per device that is pairing: d=<six digits>,<seconds left>,<address>
  const LINE = /^d=(\d{6}),(\d{1,2}),([0-9a-fA-F:.]{1,45})$/

  function read(text: string): Row[] {
    const out: Row[] = []
    for (const line of text.split('\n')) {
      const m = LINE.exec(line.trim())
      if (m && out.length < 64) out.push({ digits: m[1], left: Math.min(60, parseInt(m[2], 10)), from: m[3] })
    }
    return out
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
        rows = r.status === 200 ? read(await r.text()) : []
        problem = r.status !== 200 && r.status !== 204
      } catch {
        rows = []
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
      {#if rows.length}
        <p class="text-xs text-muted">Vários aparelhos podem parear ao mesmo tempo. Confira a linha do <strong>seu</strong> (o app mostra o endereço dele):</p>
        <ul class="my-2 divide-y divide-line" data-testid="pairing-rows">
          {#each rows as row (row.from)}
            <li class="flex flex-wrap items-center justify-between gap-x-3 py-2">
              <span class="font-mono text-xs text-muted">aparelho {row.from}</span>
              <span class="font-mono text-3xl tracking-[0.2em] text-fg" data-testid="pairing-digits" aria-label="Número de conferência: {row.digits.split('').join(' ')}">
                {row.digits.slice(0, 3)} {row.digits.slice(3)}
              </span>
              <span class="font-mono text-xs text-muted">{row.left} s</span>
            </li>
          {/each}
        </ul>
        <p class="text-xs text-muted">Se forem diferentes, <strong>não confirme</strong>: toque em Cancelar no app.</p>
      {:else if problem}
        <p class="text-xs text-offline-text">Não foi possível consultar o servidor agora.</p>
      {:else}
        <p class="text-xs text-muted">Nenhum aparelho está pareando agora. Quando você iniciar o pareamento no app, os 6 números aparecem aqui.</p>
      {/if}
    </div>
  </details>
{/if}
