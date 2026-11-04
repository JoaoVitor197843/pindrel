<script lang="ts">
  import { selection } from '../../stores/servers.svelte'

  // A room of the server, for pairing an app: a 4-digit code to type into the app, and then the six digits of that app's
  // session, shown here and nowhere else. The secret of the room (`token`) lives only in this component's memory and travels
  // in a header, never in a URL. Several people can have a room at once; each sees only their own digits.
  let open = $state(false)
  let token = $state<string | null>(null)
  let code = $state('')
  let left = $state(0)
  let phone = $state('')
  let digits = $state('')
  let error = $state('')
  let asking = false // one request for a room at a time: repeated taps do not leave rooms behind

  const lines = (text: string) => {
    const v: Record<string, string> = {}
    for (const line of text.split('\n')) {
      const i = line.indexOf('=')
      if (i > 0) v[line.slice(0, i)] = line.slice(i + 1).trim()
    }
    return v
  }

  function reset() {
    token = null
    code = digits = phone = ''
  }

  function leave() {
    const t = token
    reset()
    if (t) void fetch('/server/pair/room/close', { method: 'POST', headers: { 'x-pindrel-room': t }, keepalive: true }).catch(() => {})
  }

  async function ask() {
    if (asking) return
    asking = true
    leave()
    error = ''
    try {
      const r = await fetch('/server/pair/room', { method: 'POST', cache: 'no-store' })
      if (r.status === 429) return (error = 'Há pessoas demais pareando agora. Tente de novo em um minuto.')
      if (r.status !== 200) return (error = 'Não foi possível abrir a sala agora.')
      const v = lines(await r.text())
      if (!/^\d{4}$/.test(v.code ?? '') || !/^[0-9a-f]{32}$/.test(v.token ?? '')) return (error = 'O servidor respondeu algo inesperado.')
      token = v.token
      code = v.code
      left = Math.min(180, parseInt(v.ttl, 10) || 180)
    } catch {
      error = 'Não foi possível falar com o servidor.'
    } finally {
      asking = false
    }
  }

  // while there is a room, look at it every 2 s (the tab visible, one request at a time, three seconds at most)
  $effect(() => {
    const t = token
    if (!t) return
    let busy = false
    let ctl: AbortController | undefined
    const tick = async () => {
      if (busy || document.hidden) return
      busy = true
      ctl = new AbortController()
      const timer = setTimeout(() => ctl?.abort(), 3000)
      try {
        const r = await fetch('/server/pair/room', { cache: 'no-store', headers: { 'x-pindrel-room': t }, signal: ctl.signal })
        if (r.status === 404) {
          reset()
          error = 'Este código venceu, foi usado ou foi fechado. Gere outro.'
          return
        }
        const v = lines(await r.text())
        left = Math.min(180, parseInt(v.left, 10) || 0)
        phone = (v.phone ?? '').replace(/[^0-9a-fA-F:.]/g, '').slice(0, 45)
        const m = /^(\d{6}),(\d{1,2})$/.exec(v.d ?? '')
        digits = m ? m[1] : ''
      } catch {
        // a lost answer is tried again at the next tick
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

  // leaving the page (or this box) closes the room, so its code does not linger
  $effect(() => {
    const bye = () => leave()
    window.addEventListener('pagehide', bye)
    return () => {
      window.removeEventListener('pagehide', bye)
      leave()
    }
  })
</script>

{#if selection.tlsOffered}
  <details
    class="mx-auto mt-3 max-w-[480px] rounded-[10px] border border-line px-4 py-2 text-center"
    ontoggle={(e) => {
      open = e.currentTarget.open
      if (!open) leave()
    }}
    data-testid="pairing-code"
  >
    <summary class="cursor-pointer font-mono text-[11px] tracking-[0.6px] text-accent-text select-none">Parear um aparelho</summary>
    <div class="pt-3 pb-1" aria-live="polite">
      {#if !token}
        <p class="text-xs text-muted">Gere um código de 4 dígitos, digite-o no app e confira os 6 números que aparecerem aqui.</p>
        <button type="button" class="mt-3 rounded-[10px] bg-cream px-4 py-2 text-sm font-semibold text-on-cream" onclick={ask} data-testid="room-open">
          Gerar código de pareamento
        </button>
        {#if error}<p class="mt-2 text-xs text-offline-text" data-testid="room-error">{error}</p>{/if}
      {:else}
        <p class="text-xs text-muted">Digite no app o código da sala:</p>
        <p class="my-1 font-mono text-4xl tracking-[0.3em] text-fg" data-testid="room-code" aria-label="Código da sala: {code.split('').join(' ')}">{code}</p>
        {#if digits}
          <p class="text-xs text-muted">Confira com o app (aparelho {phone}):</p>
          <p class="my-1 font-mono text-4xl tracking-[0.2em] text-fg" data-testid="pairing-digits" aria-label="Número de conferência: {digits.split('').join(' ')}">
            {digits.slice(0, 3)} {digits.slice(3)}
          </p>
          <p class="text-xs text-muted">Se forem diferentes, <strong>não confirme</strong>: toque em Cancelar no app.</p>
        {:else}
          <p class="text-xs text-muted" data-testid="room-waiting">{phone ? 'O app entrou. Gerando os números…' : 'Esperando o app…'}</p>
        {/if}
        <p class="mt-1 text-xs text-muted">A sala fecha em {left} s. Outras pessoas pareando ao mesmo tempo não veem os seus números, nem você os delas.</p>
        <div class="mt-2 flex justify-center gap-2">
          <button type="button" class="rounded-[10px] border border-field-line px-3 py-1.5 font-mono text-[11px] tracking-[0.6px] text-fg" onclick={ask}>Gerar outro código</button>
          <button type="button" class="rounded-[10px] border border-field-line px-3 py-1.5 font-mono text-[11px] tracking-[0.6px] text-fg" onclick={leave}>Fechar</button>
        </div>
      {/if}
    </div>
  </details>
{/if}
