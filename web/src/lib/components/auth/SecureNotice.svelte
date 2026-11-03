<script lang="ts">
  import { selection } from '../../stores/servers.svelte'

  // Where the page came from decides what to say: over HTTPS the connection is private; over plain HTTP, when the server
  // has a secure side, there is a page that explains (and offers) how to use it.
  const https = window.location.protocol === 'https:'
</script>

{#if https}
  <p class="flex items-center justify-center gap-2 font-mono text-[11px] tracking-[0.6px] text-muted" data-testid="secure-notice">
    <svg class="size-3.5 shrink-0 text-accent-text" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <rect x="5" y="11" width="14" height="9" rx="2" />
      <path d="M8 11V8a4 4 0 0 1 8 0v3" />
    </svg>
    <span>Conexão segura (HTTPS)</span>
  </p>
{:else if selection.tlsOffered}
  <p class="flex flex-wrap items-center justify-center gap-x-2 gap-y-1 text-center font-mono text-[11px] tracking-[0.6px] text-offline-text" data-testid="insecure-notice">
    <span>Esta conexão não é criptografada.</span>
    <a href="/server/connect/" class="text-accent-text underline underline-offset-2">Conectar com segurança</a>
  </p>
{/if}
