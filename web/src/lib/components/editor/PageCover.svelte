<script lang="ts">
  import { COVERS } from '../../stores/blocks'
  import { DIRECTIONS, MIXES, PALETTE, coverCss, describeCover, duoSpec, monoSpec, mixSpec, soloSpec, type Direction } from '../../stores/cover'
  import type { PageEditor } from '../../stores/editor.svelte'
  import { prefs } from '../../stores/prefs.svelte'

  interface Props {
    ed: PageEditor
  }

  let { ed }: Props = $props()

  let picking = $state(false)
  const spec = $derived(ed.page?.cover ?? '')
  const css = $derived(coverCss(spec))
  const editable = $derived(ed.can('text'))
  const now = $derived(describeCover(spec))

  // the two-colour builder starts from the current choice and applies as soon as either colour or the direction changes
  let pickedFrom = $state('violeta')
  let pickedTo = $state('ferrugem')
  let pickedDir = $state<Direction>('dr')
  const from = $derived(now.kind === 'duo' ? now.a! : pickedFrom)
  const to = $derived(now.kind === 'duo' ? now.b! : pickedTo)
  const dir = $derived<Direction>(now.kind === 'duo' ? (now.dir ?? 'dr') : pickedDir)
  const duo = (a: string, b: string, d: Direction) => ed.setCover(duoSpec(a, b, d))

  const swatch = 'size-7 rounded-full border-2 ring-1 ring-line'
  const section = 'mb-1.5 font-mono text-[10px] tracking-[0.14em] text-muted uppercase'
  const pressed = (on: boolean) => (on ? 'border-fg' : 'border-transparent')
</script>

<svelte:window onmousedown={(e) => picking && !(e.target as Element).closest?.('[data-cover-menu]') && (picking = false)} />

{#if css}
  <!-- keyed on the cover, so changing it fades the new one in -->
  {#key spec}
    <div class="animate-fade relative h-40 w-full md:h-52" style:background={css} data-testid="cover"></div>
  {/key}
  {#if editable}
    <div class="relative mx-auto h-0 w-full max-w-3xl" data-cover-menu>
      <div class="absolute right-4 bottom-3 z-20 flex flex-col items-end gap-1.5 min-[480px]:flex-row min-[480px]:items-center min-[480px]:gap-2 md:right-20">
        <button
          type="button"
          class="h-8 rounded-field border border-line bg-bg/80 px-3 text-xs text-fg backdrop-blur-sm hover:bg-bg"
          aria-haspopup="dialog"
          aria-expanded={picking}
          onclick={() => (picking = !picking)}
        >
          Trocar capa
        </button>
        <button type="button" class="h-8 rounded-field border border-line bg-bg/80 px-3 text-xs text-muted backdrop-blur-sm hover:bg-bg hover:text-fg" onclick={() => ed.setCover('')}>Remover capa</button>
        {#if picking}
          <div
            role="dialog"
            aria-label="Escolher capa"
            tabindex="-1"
            class="animate-pop absolute top-full right-0 mt-2 max-h-[min(30rem,calc(100dvh-8rem))] w-[min(21rem,88vw)] overflow-y-auto rounded-field border border-line bg-surface p-3 shadow-xl"
            style:transform-origin="top right"
            onkeydown={(e) => e.key === 'Escape' && (e.stopPropagation(), (picking = false))}
          >
            <div class={section}>Combinações</div>
            <div class="mb-3 grid grid-cols-4 gap-2" role="group" aria-label="Combinações de cores">
              {#each MIXES as m (m.key)}
                <button type="button" class="h-9 rounded-field border-2 ring-1 ring-line {pressed(spec === mixSpec(m.key))}" style:background={coverCss(mixSpec(m.key))} aria-label="Capa {m.label}" aria-pressed={spec === mixSpec(m.key)} onclick={() => ed.setCover(mixSpec(m.key))}></button>
              {/each}
            </div>

            <div class={section}>Duas cores</div>
            <div class="mb-3 flex flex-col gap-2" role="group" aria-label="Duas cores">
              <div class="flex flex-wrap items-center gap-1.5" role="group" aria-label="Cor do início">
                <span class="w-9 font-mono text-[10px] text-muted">início</span>
                {#each PALETTE as c (c.id)}
                  <button type="button" class="{swatch} {pressed(now.kind === 'duo' && now.a === c.id)} !size-5" style:background={c.hex} aria-label="Início {c.label}" aria-pressed={now.kind === 'duo' && now.a === c.id} onclick={() => ((pickedFrom = c.id), duo(c.id, to, dir))}></button>
                {/each}
              </div>
              <div class="flex flex-wrap items-center gap-1.5" role="group" aria-label="Cor do fim">
                <span class="w-9 font-mono text-[10px] text-muted">fim</span>
                {#each PALETTE as c (c.id)}
                  <button type="button" class="{swatch} {pressed(now.kind === 'duo' && now.b === c.id)} !size-5" style:background={c.hex} aria-label="Fim {c.label}" aria-pressed={now.kind === 'duo' && now.b === c.id} onclick={() => ((pickedTo = c.id), duo(from, c.id, dir))}></button>
                {/each}
              </div>
              <div class="flex items-center gap-1.5" role="group" aria-label="Direção">
                <span class="w-9 font-mono text-[10px] text-muted">rumo</span>
                {#each DIRECTIONS as d (d.key)}
                  <button type="button" class="grid size-7 place-items-center rounded border text-sm {dir === d.key ? 'border-fg bg-line/60' : 'border-line hover:bg-line/40'}" aria-label={d.label} aria-pressed={dir === d.key} onclick={() => ((pickedDir = d.key), duo(from, to, d.key))}>{d.glyph}</button>
                {/each}
              </div>
            </div>

            <div class={section}>Uma cor, em degradê</div>
            <div class="mb-3 flex flex-wrap gap-1.5" role="group" aria-label="Uma cor em degradê">
              {#each PALETTE as c (c.id)}
                <button type="button" class="{swatch} {pressed(spec === monoSpec(c.id))}" style:background={coverCss(monoSpec(c.id))} aria-label="Degradê {c.label}" aria-pressed={spec === monoSpec(c.id)} onclick={() => ed.setCover(monoSpec(c.id))}></button>
              {/each}
            </div>

            <div class={section}>Cor lisa</div>
            <div class="mb-3 flex flex-wrap gap-1.5" role="group" aria-label="Cor lisa">
              {#each PALETTE as c (c.id)}
                <button type="button" class="{swatch} {pressed(spec === soloSpec(c.id))}" style:background={coverCss(soloSpec(c.id))} aria-label="Lisa {c.label}" aria-pressed={spec === soloSpec(c.id)} onclick={() => ed.setCover(soloSpec(c.id))}></button>
              {/each}
            </div>

            <div class={section}>Clássicas</div>
            <div class="mb-3 flex flex-wrap gap-1.5" role="group" aria-label="Capas clássicas">
              {#each COVERS as c (c.key)}
                <button type="button" class="{swatch} {pressed(spec === c.key)}" style:background={c.css} aria-label="Capa {c.label}" aria-pressed={spec === c.key} onclick={() => ed.setCover(c.key)}></button>
              {/each}
            </div>

            <div class={section}>Ícone sobre a capa</div>
            <div class="flex gap-1.5" role="group" aria-label="Posição do ícone">
              <button type="button" class="h-8 flex-1 rounded border text-xs {prefs.iconAlign === 'left' ? 'border-fg bg-line/60' : 'border-line hover:bg-line/40'}" aria-pressed={prefs.iconAlign === 'left'} onclick={() => prefs.setIconAlign('left')}>Na coluna</button>
              <button type="button" class="h-8 flex-1 rounded border text-xs {prefs.iconAlign === 'center' ? 'border-fg bg-line/60' : 'border-line hover:bg-line/40'}" aria-pressed={prefs.iconAlign === 'center'} onclick={() => prefs.setIconAlign('center')}>No centro</button>
            </div>
          </div>
        {/if}
      </div>
    </div>
  {/if}
{/if}
