<script lang="ts">
  import BrandRow from './BrandRow.svelte'
  import ServerSelector from './ServerSelector.svelte'

  interface Props {
    onaddserver?: () => void
  }

  let { onaddserver }: Props = $props()
</script>

<!-- Dark header (narrow layout): brand, server selector and tagline. -->
<header class="rounded-b-[32px] border-b border-line bg-surface px-6 pt-4 pb-7">
  <div class="flex items-center justify-between gap-2">
    <BrandRow />
    <ServerSelector onadd={onaddserver} />
  </div>
  <p class="mt-4 font-serif text-xl">
    Suas notas. <em class="text-accent-line">Seu servidor.</em>
  </p>
</header>
