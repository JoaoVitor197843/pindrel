<script lang="ts">
  interface Props {
    onclose: () => void
  }

  let { onclose }: Props = $props()
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && onclose()} />

<div class="fixed inset-0 z-30 flex items-end justify-center bg-black/60 sm:items-center">
  <button type="button" aria-label="Fechar" class="absolute inset-0 cursor-default" onclick={onclose}></button>
  <div
    role="dialog"
    aria-modal="true"
    aria-labelledby="recovery-title"
    class="relative w-full max-w-md rounded-t-3xl border border-line bg-surface p-6 sm:rounded-3xl"
  >
    <h2 id="recovery-title" class="font-serif text-2xl">Chave de recuperação</h2>
    <p class="mt-2 leading-[1.4] text-muted">Digite o código de recuperação gerado quando você criou a conta.</p>
    <label for="recovery-code" class="sr-only">Código de recuperação</label>
    <input
      id="recovery-code"
      type="text"
      autocomplete="off"
      placeholder="XXXX-XXXX-XXXX"
      class="mt-4 w-full rounded-field border border-line bg-surface px-4 py-4 font-mono tracking-[2px] uppercase placeholder:text-muted focus:border-accent-line focus:outline-none"
    />
    <button
      type="button"
      onclick={onclose}
      class="mt-4 h-13 w-full rounded-field bg-cream font-semibold text-on-cream"
    >
      Recuperar acesso
    </button>
  </div>
</div>
