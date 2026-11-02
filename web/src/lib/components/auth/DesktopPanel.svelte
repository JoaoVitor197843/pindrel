<script lang="ts">
  import BrandRow from './BrandRow.svelte'
  import ServerSelector from './ServerSelector.svelte'

  interface Props {
    onaddserver?: () => void
  }

  let { onaddserver }: Props = $props()

  const features = [
    {
      tag: 'SELF-HOSTED',
      title: 'Roda no seu hardware',
      body: 'Nenhuma nota sai do seu servidor. Sem SaaS, sem telemetria, sem assinatura.',
    },
    {
      tag: 'BLOCOS',
      title: 'Blocos aninhados',
      body: 'Páginas dentro de páginas, listas dentro de listas — a estrutura acompanha o pensamento.',
    },
    {
      tag: 'COFRE',
      title: 'Cofre com criptografia',
      body: 'Marque uma página como cofre e ela é gravada cifrada, com chave derivada da sua senha.',
    },
  ]
</script>

<!-- Left panel (wide layout): brand, tagline, selling points and footer. -->
<aside class="flex min-h-screen flex-col border-r border-line bg-surface px-12 pt-10 pb-8">
  <div class="flex items-center justify-between gap-2">
    <BrandRow />
    <ServerSelector onadd={onaddserver} />
  </div>

  <div class="flex flex-1 items-center">
    <div class="w-full max-w-[480px]">
      <h2 class="font-serif text-[44px] leading-[1.15]">
        Suas notas.<br />
        <em class="text-accent-line">Seu servidor.</em>
      </h2>
      <p class="mt-6 text-[15px] leading-normal text-muted">
        Um espaço de escrita para você e sua família, rodando na sua própria máquina — sem contas na nuvem de ninguém.
      </p>
      <ul class="mt-6">
        {#each features as feature (feature.tag)}
          <li class="flex gap-6 border-t border-line py-4">
            <span class="w-28 shrink-0 pt-0.5 font-mono text-[11px] tracking-[1.4px] text-accent-line">{feature.tag}</span>
            <div>
              <h3 class="font-semibold">{feature.title}</h3>
              <p class="mt-1 text-[13px] leading-[1.45] text-muted">{feature.body}</p>
            </div>
          </li>
        {/each}
      </ul>
    </div>
  </div>

  <p class="font-mono text-xs tracking-[0.4px] text-muted">pindrel v0.9.5 &nbsp;•&nbsp; licença AGPL-3.0</p>
</aside>
