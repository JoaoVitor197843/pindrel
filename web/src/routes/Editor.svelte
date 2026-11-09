<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte'
  import { canVault } from '../lib/capabilities'
  import { prefetchEngine } from '../lib/components/editor/rich/engine'
  import { MediaQuery } from 'svelte/reactivity'
  import Icon from '../lib/components/dashboard/Icon.svelte'
  import Lazy from '../lib/components/dashboard/Lazy.svelte'
  import VaultPrompt from '../lib/components/dashboard/VaultPrompt.svelte'
  import ConfirmDialog from '../lib/components/editor/ConfirmDialog.svelte'
  import ExportMenu from '../lib/components/editor/ExportMenu.svelte'
  import MoreMenu, { type MoreItem } from '../lib/components/editor/MoreMenu.svelte'
  import PageCover from '../lib/components/editor/PageCover.svelte'
  import PageIcon from '../lib/components/editor/PageIcon.svelte'
  import DockToggle from '../lib/components/editor/DockToggle.svelte'
  import PageProps from '../lib/components/editor/PageProps.svelte'
  import SelectionToolbar from '../lib/components/editor/SelectionToolbar.svelte'
  import ToggleBlock from '../lib/components/editor/ToggleBlock.svelte'
  import TocBlock from '../lib/components/editor/TocBlock.svelte'
  import BookmarkBlock from '../lib/components/editor/BookmarkBlock.svelte'
  import MediaBlock from '../lib/components/editor/MediaBlock.svelte'
  import FileBlock from '../lib/components/editor/FileBlock.svelte'
  import PageLinkBlock from '../lib/components/editor/PageLinkBlock.svelte'
  import { applyEdit } from '../lib/components/editor/fieldEdit'
  import ShareModal from '../lib/components/editor/ShareModal.svelte'
  import SidePanel from '../lib/components/editor/SidePanel.svelte'
  import BlockRow from '../lib/components/editor/BlockRow.svelte'
  import ChecklistBlock from '../lib/components/editor/ChecklistBlock.svelte'
  import CodeBlock from '../lib/components/editor/CodeBlock.svelte'
  import ImageBlock from '../lib/components/editor/ImageBlock.svelte'
  import InsertMenu from '../lib/components/editor/InsertMenu.svelte'
  import SecureBlock from '../lib/components/editor/SecureBlock.svelte'
  import SpoilerBlock from '../lib/components/editor/SpoilerBlock.svelte'
  import TableBlock from '../lib/components/editor/TableBlock.svelte'
  import TextBlock from '../lib/components/editor/TextBlock.svelte'
  import { autosize, place } from '../lib/components/editor/autosize'
  import { ms } from '../lib/motion'
  import { ago, blockTypeForFile, isTextType, levelOf, numbering, toneOf, type Block, type BlockType, type HeadingLevel } from '../lib/stores/blocks'
  import { toggleMark, type Mark } from '../lib/stores/inline'
  import { barLock, instances, type RichInstance } from '../lib/components/editor/rich/engine'
  import { Dock, dockScale } from '../lib/stores/dock.svelte'
  import { PageEditor } from '../lib/stores/editor.svelte'
  import { toast } from '../lib/stores/toast.svelte'
  import type { Workspace } from '../lib/stores/workspace.svelte'

  interface Props {
    ws: Workspace
    id: string
    onback: () => void
    /** Opens another page (a related one, or the copy just made). */
    onopen?: (id: string) => void
  }

  let { ws, id, onback, onopen }: Props = $props()

  // svelte-ignore state_referenced_locally
  const ed = new PageEditor(ws, id)
  // bring the text editor in while the connection is up, so a page opened later without one can still be edited
  onMount(() => {
    if (ed.can('text')) prefetchEngine()
  })
  onDestroy(() => ed.destroy())

  let root: HTMLElement | undefined = $state()

  // Two panels beside the page: the properties on the left, the panel (outline, details, related, actions) on the right.
  // Wide screens dock them (open at first); narrower ones keep them as drawers, closed, opened by an arrow on the edge of
  // the screen; below that there is no room for the arrow and the header carries the buttons instead.
  const wide = new MediaQuery('min-width: 1340px')
  const roomForArrows = new MediaQuery('min-width: 360px')
  // on a short, narrow screen the header keeps only the back arrow, the export and a menu with the rest
  const compact = new MediaQuery('max-width: 479px')
  const panel = new Dock('pindrel:editor-panel')
  const propsDock = new Dock('pindrel:editor-props')
  const panelOpen = $derived(panel.isOpen(wide.current))
  const propsOpen = $derived(propsDock.isOpen(wide.current))
  let mainH = $state(0)
  let winW = $state(0)
  const scale = $derived(dockScale(winW))

  function jump(blockId: string) {
    const el = root?.querySelector<HTMLElement>(`[data-block-id="${blockId}"]`)
    el?.scrollIntoView?.({ block: 'start', behavior: ms(250) ? 'smooth' : 'auto' })
    // a block far away is an empty box of an estimated height: once it is drawn the real one may differ, so land again
    if (el?.getAttribute('data-lazy') === 'empty') setTimeout(() => root?.querySelector(`[data-block-id="${blockId}"]`)?.scrollIntoView?.({ block: 'start' }), 120)
    if (!wide.current) panel.closeDrawer()
  }

  function duplicate() {
    const made = ed.duplicate()
    if (!made) return
    toast.show(made.images ? 'Página duplicada (as imagens não foram copiadas)' : 'Página duplicada')
    onopen?.(made.id)
  }

  const STARTERS: { type: BlockType; label: string }[] = [
    { type: 'paragraph', label: 'Texto' },
    { type: 'heading', label: 'Título' },
    { type: 'checklist', label: 'Checklist' },
    { type: 'table', label: 'Tabela' },
    { type: 'code', label: 'Código' },
  ]
  let draft = $state('')
  /** Which insert menu is open: a block's id, or 'draft' for the empty last line. */
  let menuFor = $state<string | null>(null)
  /** The menu came from typing "/" in this empty paragraph, which the new block then replaces. */
  let replacing = $state<string | null>(null)
  let unlocking = $state(false)
  let sharing = $state<'access' | 'add' | null>(null)
  let deleting = $state(false)
  let dragFrom = $state<number | null>(null)
  let dropAt = $state<number | null>(null)

  const page = $derived(ed.page)
  const gated = $derived(!!page?.locked && !ws.vaultUnlocked)
  const labels: Record<Block['type'], string> = {
    paragraph: 'Parágrafo',
    heading: 'Título de seção',
    quote: 'Citação',
    callout: 'Destaque',
    toggle: 'Toggle',
    divider: 'Divisor',
    checklist: 'Checklist',
    code: 'Bloco de código',
    spoiler: 'Spoiler',
    secure: 'Bloco seguro',
    table: 'Tabela',
    image: 'Imagem',
    bullet: 'Item de lista',
    numbered: 'Item numerado',
    toc: 'Sumário',
    bookmark: 'Link',
    pagelink: 'Link para página',
    video: 'Vídeo',
    audio: 'Áudio',
    pdf: 'PDF',
    file: 'Arquivo',
  }
  // the number each item of a numbered list shows, counted from the page's blocks (never stored)
  const numbers = $derived(numbering(ed.blocks))
  const BULLETS = ['•', '◦', '▪']
  /** Deleting cannot be undone when the trash is off, for a vault page, in the trash itself, or for a page I was given. */
  const permanent = $derived(!!page && (page.trashed || page.locked || page.sharedBy !== null || !ws.settings.useTrash))

  // where the page lives, for the path at the top
  const place_ = $derived(page?.trashed ? 'Lixeira' : page?.locked ? 'Cofre' : page?.sharedBy ? 'Compartilhadas comigo' : null)

  // zen mode: only the words; the chrome, the panel, the properties and the block handles go away
  let zen = $state(false)

  const moreItems = $derived.by(() => {
    const items: MoreItem[] = [{ label: 'Modo zen', icon: 'zen', onclick: () => (zen = true) }]
    if (!roomForArrows.current) {
      items.push({ label: 'Propriedades', icon: 'page', onclick: () => propsDock.toggle(false) })
      items.push({ label: 'Painel', icon: 'panel', onclick: () => panel.toggle(false) })
    }
    if (page && ed.can('delete')) items.push({ label: page.trashed ? 'Excluir definitivamente' : 'Excluir página', icon: 'trash', danger: true, onclick: () => (deleting = true) })
    return items
  })

  // the selection toolbar follows a text field that has something selected
  let fmtField = $state<HTMLTextAreaElement | null>(null)
  let fmtRich = $state<{ inst: RichInstance; el: HTMLElement } | null>(null)
  function syncSelection() {
    // the link address field of the bar has the focus: the bar and the selection it works on stay as they are
    if (barLock.linking) return
    const el = document.activeElement
    const host = el?.closest?.('[data-rich]') as HTMLElement | null | undefined
    const inst = host ? instances.get(host) : undefined
    if (host && inst && root?.contains(host) && ed.can('text')) {
      const { from, to } = inst.selection()
      fmtField = null
      fmtRich = from !== to ? { inst, el: host } : null
      return
    }
    fmtRich = null
    if (el instanceof HTMLTextAreaElement && el.matches('[data-fmt]') && root?.contains(el) && ed.can('text') && el.selectionStart !== el.selectionEnd) {
      fmtField = el
    } else if (!el?.closest?.('[aria-label="Formatar texto"]')) fmtField = null
  }

  function fmtKey(e: KeyboardEvent) {
    if (!(e.ctrlKey || e.metaKey) || e.altKey) return
    const key = e.key.toLowerCase()
    // Ctrl+B / I / U like everywhere; strike is Ctrl+Shift+S (Notion) or Ctrl+Shift+X (Gmail)
    const mark: Mark | null = e.shiftKey ? (key === 's' || key === 'x' ? 'strike' : key === 'h' ? 'highlight' : null) : key === 'b' ? 'bold' : key === 'i' ? 'italic' : key === 'u' ? 'underline' : null
    if (!mark) return
    const el = e.target as HTMLTextAreaElement
    if (!el.matches?.('[data-fmt]') || !ed.can('text')) return
    e.preventDefault()
    applyEdit(el, toggleMark(el.value, el.selectionStart, el.selectionEnd, mark))
  }

  function duplicateBlock(blockId: string) {
    const made = ed.duplicateBlock(blockId)
    if (!made) return void toast.show(ed.blocks.length >= 500 ? 'Limite de blocos da página atingido' : 'Este bloco não pode ser duplicado')
    void focusBlock(made.id, 'end')
  }

  /** About how tall a block is, for the empty box it leaves while far from the screen. */
  function estimateHeight(b: Block): number {
    switch (b.type) {
      case 'heading':
        return levelOf(b) === 1 ? 56 : levelOf(b) === 3 ? 38 : 44
      case 'toc':
        return 90
      case 'bookmark':
      case 'pagelink':
      case 'pdf':
      case 'file':
        return 76
      case 'video':
        return 300
      case 'audio':
        return 110
      case 'checklist':
        return 12 + 34 * b.items.length
      case 'table':
        return 80 + 44 * b.rows.length
      case 'code':
        return 60 + 23 * b.text.split('\n').length
      case 'image':
        return 220
      case 'divider':
        return 30
      case 'paragraph':
      case 'quote':
      case 'callout':
      case 'toggle':
      case 'spoiler':
      case 'secure':
      case 'bullet':
      case 'numbered':
        return Math.max(1, Math.ceil(b.text.length / 70)) * 28
    }
  }

  async function focusBlock(blockId: string, where: 'start' | 'end' = 'end') {
    await tick()
    place(root?.querySelector<HTMLInputElement | HTMLTextAreaElement>(`[data-block-id="${blockId}"] [data-nav]`), where)
  }

  function focusTitle() {
    place(root?.querySelector<HTMLTextAreaElement>('[data-title]'))
  }

  function confirmDelete() {
    const p = page
    if (!p) return
    deleting = false
    // decided before the page moves: afterwards it would count as "already in the trash"
    const forever = permanent
    if (forever) ws.deleteForever(id)
    else ws.trash(id)
    toast.show(forever ? 'Página excluída' : 'Movida para a lixeira')
    onback()
  }

  const hasFiles = (e: DragEvent) => !!e.dataTransfer?.types?.includes('Files')

  /** Files dropped on the page become blocks, one after the other at the end, each sent to the server. */
  function dropFiles(list: File[]) {
    if (!ed.can('blocks')) return
    if (!ed.files.available) return void toast.show('Entre em um servidor para enviar arquivos')
    let after = ed.blocks.at(-1)?.id ?? null
    for (const file of list.slice(0, 10)) {
      const kind = blockTypeForFile(file.type, 1)
      const made = ed.insert(kind === 'image' && !ed.can('images') ? 'file' : kind, after)
      if (!made) return void toast.show('Limite de blocos da página atingido')
      ed.uploadInto(made.id, file)
      after = made.id
    }
  }

  function pick(type: BlockType, afterId: string | null, opts: { level?: HeadingLevel } = {}) {
    const replace = replacing
    menuFor = null
    replacing = null
    const made = ed.insert(type, afterId, opts)
    if (!made) return void toast.show('Limite de blocos da página atingido')
    if (replace) ed.remove(replace)
    void focusBlock(made.id, 'start')
  }

  /** Removes a block and puts the caret at the end of the one before it (or the title). */
  function removeBlock(blockId: string) {
    const i = ed.blocks.findIndex((b) => b.id === blockId)
    const before = ed.blocks[i - 1]
    ed.remove(blockId)
    if (before) void focusBlock(before.id, 'end')
    else focusTitle()
  }

  /** Enter on an empty checklist item ends the list: a paragraph follows it. */
  function exitChecklist(blockId: string) {
    const made = ed.insert('paragraph', blockId)
    if (made) void focusBlock(made.id, 'start')
  }

  function slash(blockId: string) {
    replacing = blockId
    menuFor = blockId
  }

  function titleKey(e: KeyboardEvent) {
    if (e.key !== 'Enter' || e.isComposing) return
    e.preventDefault()
    const first = ed.blocks[0] ?? ed.insert('paragraph')
    if (first) void focusBlock(first.id, 'start')
  }

  function draftInput(e: Event & { currentTarget: HTMLTextAreaElement }) {
    const el = e.currentTarget
    if (el.value === '/') {
      draft = ''
      el.value = ''
      menuFor = 'draft'
      return
    }
    if (!el.value) return
    const made = ed.insert('paragraph')
    if (made && made.type === 'paragraph') {
      ed.setText(made.id, el.value)
      draft = ''
      el.value = ''
      void focusBlock(made.id, 'end')
    }
  }

  /** Arrows leave a field only at its edge: the caret moves through the text first. */
  function navKey(e: KeyboardEvent) {
    const key = e.key
    if (key !== 'ArrowUp' && key !== 'ArrowDown' && key !== 'ArrowLeft' && key !== 'ArrowRight') return
    if (e.shiftKey || e.altKey || e.ctrlKey || e.metaKey || e.isComposing) return
    const el = e.target as HTMLInputElement | HTMLTextAreaElement
    if (!el.matches?.('[data-nav]') || el.selectionStart !== el.selectionEnd) return
    const prev = key === 'ArrowUp' || key === 'ArrowLeft'
    if (prev ? el.selectionStart !== 0 : el.selectionStart !== el.value.length) return
    const navs = [...(root?.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('[data-nav]') ?? [])]
    const target = navs[navs.indexOf(el) + (prev ? -1 : 1)]
    if (!target) return
    e.preventDefault()
    place(target, prev ? 'end' : 'start')
  }

  function dragStart(e: DragEvent, index: number, blockId: string) {
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = 'move'
      e.dataTransfer.setData('text/plain', blockId)
    }
    dragFrom = index
  }

  function dragOver(e: DragEvent, index: number) {
    if (dragFrom === null) return
    e.preventDefault()
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    dropAt = index + (e.clientY > r.top + r.height / 2 ? 1 : 0)
  }

  function dragDrop(e: DragEvent) {
    if (dragFrom === null || dropAt === null) return
    e.preventDefault()
    ed.move(dragFrom, dropAt)
    dragEnd()
  }

  // touch and pen: the handle reports the finger, this finds the gap it is over and scrolls when it nears an edge
  let fingerY = 0
  let scrollTimer: ReturnType<typeof requestAnimationFrame> | undefined

  function gapAt(y: number): number {
    const rows = [...(root?.querySelectorAll<HTMLElement>('[data-block-id]') ?? [])]
    const i = rows.findIndex((row) => {
      const r = row.getBoundingClientRect()
      return y < r.top + r.height / 2
    })
    return i === -1 ? rows.length : i
  }

  function autoScroll() {
    if (dragFrom === null || !root) return
    const r = root.getBoundingClientRect()
    const edge = 72
    if (fingerY < r.top + edge) root.scrollTop -= Math.ceil((r.top + edge - fingerY) / 5)
    else if (fingerY > r.bottom - edge) root.scrollTop += Math.ceil((fingerY - (r.bottom - edge)) / 5)
    dropAt = gapAt(fingerY)
    scrollTimer = requestAnimationFrame(autoScroll)
  }

  function pointerDrag(phase: 'start' | 'move' | 'end' | 'cancel', y: number, index: number) {
    if (phase === 'start') {
      dragFrom = index
      fingerY = y
      scrollTimer = requestAnimationFrame(autoScroll)
    } else if (phase === 'move') {
      fingerY = y
      dropAt = gapAt(y)
    } else {
      if (scrollTimer !== undefined) cancelAnimationFrame(scrollTimer)
      scrollTimer = undefined
      if (phase === 'end' && dragFrom !== null && dropAt !== null) ed.move(dragFrom, dropAt)
      dragEnd()
    }
  }

  onDestroy(() => scrollTimer !== undefined && cancelAnimationFrame(scrollTimer))

  function dragEnd() {
    dragFrom = null
    dropAt = null
  }

  function edge(i: number): 'before' | 'after' | null {
    if (dragFrom === null || dropAt === null) return null
    if (dropAt === i) return 'before'
    return dropAt === i + 1 && i === ed.blocks.length - 1 ? 'after' : null
  }
</script>

<svelte:window bind:innerWidth={winW} onkeydown={(e) => e.key === 'Escape' && zen && !e.defaultPrevented && (zen = false)} />
<svelte:document onselectionchange={syncSelection} />

<div class="flex h-dvh flex-col bg-bg text-fg">
  {#if !zen}
  <header class="flex items-center justify-between gap-2 border-b border-line px-2 py-3 min-[400px]:px-4 md:gap-3 md:px-8">
    <div class="flex min-w-0 items-center gap-1">
      <button type="button" class="inline-flex h-10 shrink-0 items-center gap-2 rounded-field px-2 text-sm text-accent-text hover:bg-line/40" onclick={onback}>
        <span aria-hidden="true">←</span><span class="max-[400px]:sr-only">Dashboard</span>
      </button>
      {#if page && !gated}
        <nav aria-label="Caminho" class="hidden min-w-0 items-center gap-1.5 text-sm text-muted md:flex">
          {#if place_}<span aria-hidden="true">/</span><span class="shrink-0">{place_}</span>{/if}
          <span aria-hidden="true">/</span>
          <span class="truncate text-fg" aria-current="page">{page.icon} {page.title || 'Sem título'}</span>
          <span class="shrink-0 pl-2 font-mono text-xs" data-testid="crumb-edited">editada {ago(page.updated)}</span>
        </nav>
      {/if}
    </div>
    <div class="flex shrink-0 items-center gap-1 sm:gap-2">
      {#if compact.current}
        {#if page && ed.can('export')}<ExportMenu {ed} />{/if}
        {#if page && !gated}<MoreMenu items={moreItems} />{/if}
      {:else}
        {#if page && !gated}
          <button
            type="button"
            class="inline-flex h-10 items-center gap-2 rounded-field px-2.5 text-sm text-muted hover:bg-line/40 hover:text-fg md:border md:border-line md:px-3"
            aria-label="Modo zen"
            onclick={() => (zen = true)}
          >
            <Icon name="zen" size={16} /><span class="hidden md:inline">Zen</span>
          </button>
          {#if !roomForArrows.current}
            <button
              type="button"
              class="inline-flex h-10 items-center gap-2 rounded-field px-2.5 text-sm text-muted hover:bg-line/40 hover:text-fg {propsOpen ? 'bg-line/40 text-fg' : ''}"
              aria-pressed={propsOpen}
              aria-label="Propriedades da página"
              onclick={() => propsDock.toggle(false)}
            >
              <Icon name="page" size={16} />
            </button>
            <button
              type="button"
              class="inline-flex h-10 items-center gap-2 rounded-field px-2.5 text-sm text-muted hover:bg-line/40 hover:text-fg {panelOpen ? 'bg-line/40 text-fg' : ''}"
              aria-pressed={panelOpen}
              aria-label="Painel da página"
              onclick={() => panel.toggle(false)}
            >
              <Icon name="panel" size={16} />
            </button>
          {/if}
        {/if}
        {#if page && ed.can('export')}<ExportMenu {ed} />{/if}
        {#if page && ed.can('delete')}
          <button
            type="button"
            class="inline-flex h-10 items-center gap-2 rounded-field px-2.5 text-sm text-offline-text hover:bg-offline/10 md:border md:border-offline/50 md:px-3"
            aria-label={page.trashed ? 'Excluir página definitivamente' : 'Excluir página'}
            onclick={() => (deleting = true)}
          >
            <Icon name="trash" size={16} /><span class="hidden md:inline">Excluir</span>
          </button>
        {/if}
      {/if}
      <div class="ml-1 flex items-center gap-2 font-mono text-xs text-muted sm:ml-3" role="status">
        <span class="hidden sm:inline">{ed.save === 'saving' ? 'salvando…' : 'salvo automaticamente'}</span>
        <span class="sr-only sm:hidden">{ed.save === 'saving' ? 'salvando…' : 'salvo automaticamente'}</span>
        <span class="size-2 rounded-full {ed.save === 'saving' ? 'bg-tag-gold' : 'bg-accent-line'}"></span>
      </div>
    </div>
  </header>
  {/if}

  <main class="min-h-0 flex-1 overflow-y-auto" bind:this={root} bind:clientHeight={mainH}>
    {#if !page}
      <div class="mx-auto max-w-xl px-4 py-24 text-center">
        <h1 class="font-serif text-3xl">Página não encontrada</h1>
        <p class="mt-2 text-sm text-muted">Ela pode ter sido excluída de vez.</p>
        <button type="button" class="mt-6 h-11 rounded-field bg-cream px-4 text-sm font-medium text-on-cream" onclick={onback}>Voltar ao dashboard</button>
      </div>
    {:else if gated}
      <div class="mx-auto flex max-w-xl flex-col items-center gap-3 px-4 py-24 text-center">
        <span class="text-muted"><Icon name="lock" size={32} /></span>
        <h1 class="font-serif text-3xl">{page.title}</h1>
        {#if canVault()}
          <p class="text-sm text-muted">Esta página está no cofre: o conteúdo só abre com a senha mestra.</p>
          <button type="button" class="mt-3 h-11 rounded-field bg-cream px-4 text-sm font-medium text-on-cream" onclick={() => (unlocking = true)}>Desbloquear</button>
        {:else}
          <p class="text-sm text-muted">Esta página está no cofre, que só abre em HTTPS ou em localhost. Acesse o servidor por um endereço seguro.</p>
        {/if}
      </div>
    {:else}
      {#if wide.current && !zen}
        <!-- Docked beside the page, never part of its flow: opening or closing one must not move the page. A strip of zero
             height sticks to the top of the scroll area, so the panels and their arrows are always in the middle of what
             is on screen, whether the page is short, long or has a cover. -->
        <div class="sticky top-0 z-20 h-0">
          <div class="absolute top-0 left-0 hidden items-start xl:flex" data-testid="dock-left" style:zoom={scale}>
            <div class="flex" style:height="{mainH / scale}px">
              <div class="flex w-12 shrink-0 items-center justify-center">
                <DockToggle side="left" open={propsOpen} label={propsOpen ? 'Fechar propriedades' : 'Abrir propriedades'} onclick={() => propsDock.toggle(true)} />
              </div>
              {#if propsOpen}
                <div class="animate-slide-left my-4 w-60 overflow-x-hidden overflow-y-auto rounded-field border border-line bg-surface/85 p-4 backdrop-blur-sm [scrollbar-width:thin]">
                  <aside aria-label="Propriedades da página" class="flex flex-col gap-5">
                    <p class="font-serif text-xl">Propriedades</p>
                    <PageProps {ed} onshare={(tab) => (sharing = tab)} />
                  </aside>
                </div>
              {/if}
            </div>
          </div>
          <div class="absolute top-0 right-0 hidden items-start justify-end xl:flex" data-testid="dock" style:zoom={scale}>
            <div class="flex" style:height="{mainH / scale}px">
              {#if panelOpen}
                <div class="animate-slide-right my-4 w-60 overflow-x-hidden overflow-y-auto rounded-field border border-line bg-surface/85 p-4 backdrop-blur-sm [scrollbar-width:thin]">
                  <SidePanel {ed} onjump={jump} {onopen} onduplicate={duplicate} />
                </div>
              {/if}
              <div class="flex w-12 shrink-0 items-center justify-center">
                <DockToggle side="right" open={panelOpen} label={panelOpen ? 'Fechar painel' : 'Abrir painel'} onclick={() => panel.toggle(true)} />
              </div>
            </div>
          </div>
        </div>
      {/if}
      {#if !zen}<PageCover {ed} />{/if}
      <div class="animate-fade relative w-full">
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
      <article class="mx-auto w-full min-w-0 px-7 pb-32 min-[360px]:px-7 md:px-20 {zen ? 'max-w-2xl pt-24' : 'max-w-3xl pt-10'}" onkeydown={(e) => (navKey(e), fmtKey(e))}
        ondragover={(e) => hasFiles(e) && e.preventDefault()}
        ondrop={(e) => {
          if (!hasFiles(e)) return
          e.preventDefault()
          dropFiles([...(e.dataTransfer?.files ?? [])])
        }}
      >
        {#if ed.readOnly}
          <div class="mb-6 flex flex-wrap items-center gap-3 rounded-field border border-line bg-surface px-4 py-3 text-sm" role="status">
            Esta página está na lixeira e não pode ser editada.
            <button type="button" class="ml-auto h-9 rounded-field border border-field-line px-3 hover:bg-line/40" onclick={() => ws.restore(id)}>Restaurar</button>
          </div>
        {/if}

        {#if !zen || page.icon}<PageIcon {ed} />{/if}

        <div role="heading" aria-level="1" aria-label={page.title || 'Sem título'}>
          <textarea
            data-nav
            data-title
            rows="1"
            value={page.title}
            oninput={(e) => ed.setTitle(e.currentTarget.value)}
            onkeydown={titleKey}
            use:autosize={page.title}
            readonly={!ed.can('text')}
            maxlength="120"
            spellcheck="false"
            aria-label="Título da página"
            placeholder="Sem título"
            class="block w-full resize-none overflow-hidden bg-transparent font-serif text-4xl leading-tight font-bold break-words placeholder:text-muted/60 md:text-[2.6rem]"
          ></textarea>
        </div>

        <div class="h-8"></div>

        <div class="flex flex-col gap-3 {zen ? 'zen-dim' : ''}">
          {#each ed.blocks as block, i (block.id)}
            <Lazy id={block.id} blockId={block.id} estimate={estimateHeight(block)} eager={i < 14}>
              {#snippet children(first)}
            <BlockRow
              id={block.id}
              label={labels[block.type]}
              index={i}
              count={ed.blocks.length}
              readOnly={!ed.can('blocks') || zen}
              turnable={isTextType(block.type)}
              kind={block.type}
              canDuplicate={block.type !== 'image' || !!block.fileId}
              onduplicate={() => duplicateBlock(block.id)}
              onturn={(t, o) => ed.turnInto(block.id, t, o)}
              level={block.type === 'heading' ? levelOf(block) : 2}
              headingToggle={block.type === 'heading' && !!block.toggle}
              tone={block.type === 'callout' ? toneOf(block) : 'info'}
              ontone={(t) => ed.setTone(block.id, t)}
              disabledTypes={ed.can('images') ? [] : ['image']}
              menuOpen={menuFor === block.id && replacing === null}
              dropEdge={edge(i)}
              onplus={() => ((replacing = null), (menuFor = menuFor === block.id ? null : block.id))}
              onpick={(t, o) => pick(t, block.id, o)}
              onclosemenu={() => ((menuFor = null), (replacing = null))}
              onmove={(d) => ed.moveBy(block.id, d)}
              onremove={() => removeBlock(block.id)}
              ondragstart={(e) => dragStart(e, i, block.id)}
              ondragend={dragEnd}
              ondragover={(e) => dragOver(e, i)}
              ondrop={dragDrop}
              dragging={dragFrom === i}
              enter={first}
              onpointerdrag={(phase, y) => pointerDrag(phase, y, i)}
            >
              {#if block.type === 'paragraph'}
                <TextBlock {ed} {block} label="Parágrafo" onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'heading' && block.toggle}
                <ToggleBlock {ed} {block} onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'heading'}
                <TextBlock {ed} {block} variant="heading" label="Título de seção" onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'quote'}
                <TextBlock {ed} {block} label="Citação" onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'callout'}
                <TextBlock {ed} {block} label="Destaque" onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'bullet' || block.type === 'numbered'}
                <div class="flex items-start" style:padding-left="{(block.indent ?? 0) * 1.75}rem">
                  <span class="w-7 shrink-0 pr-2 text-right text-[16.5px] leading-[1.68] text-muted select-none" aria-hidden="true">{block.type === 'bullet' ? BULLETS[(block.indent ?? 0) % BULLETS.length] : `${numbers.get(block.id) ?? 1}.`}</span>
                  <div class="min-w-0 flex-1">
                    <TextBlock {ed} {block} label={block.type === 'bullet' ? 'Item de lista' : 'Item numerado'} onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
                  </div>
                </div>
              {:else if block.type === 'toc'}
                <TocBlock {ed} onjump={jump} />
              {:else if block.type === 'bookmark'}
                <BookmarkBlock {ed} {block} />
              {:else if block.type === 'video' || block.type === 'audio' || block.type === 'pdf'}
                <MediaBlock {ed} {block} />
              {:else if block.type === 'file'}
                <FileBlock {ed} {block} />
              {:else if block.type === 'pagelink'}
                <PageLinkBlock {ed} {block} {onopen} />
              {:else if block.type === 'toggle'}
                <ToggleBlock {ed} {block} onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'divider'}
                <hr class="my-3 border-line" />
              {:else if block.type === 'checklist'}
                <ChecklistBlock {ed} {block} onremove={removeBlock} onexit={exitChecklist} />
              {:else if block.type === 'code'}
                <CodeBlock {ed} {block} />
              {:else if block.type === 'spoiler'}
                <SpoilerBlock {ed} {block} onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'secure'}
                <SecureBlock {ed} {block} onsplit={(n) => focusBlock(n, 'start')} onremove={removeBlock} onslash={slash} />
              {:else if block.type === 'table'}
                <TableBlock {ed} {block} />
              {:else if block.type === 'image'}
                <ImageBlock {ed} {block} />
              {/if}
            </BlockRow>
              {/snippet}
            </Lazy>
            {#if menuFor === block.id && replacing === block.id}
              <div class="relative -mt-3"><InsertMenu onpick={(t, o) => pick(t, block.id, o)} onclose={() => ((menuFor = null), (replacing = null))} disabled={ed.can('images') ? [] : ['image']} /></div>
            {/if}
          {/each}

          {#if ed.can('blocks')}
            <div class="relative">
              <textarea
                data-nav
                data-draft
                rows="1"
                bind:value={draft}
                oninput={draftInput}
                onkeydown={(e) => e.key === 'Enter' && e.preventDefault()}
                use:autosize={draft}
                maxlength="20000"
                spellcheck="false"
                aria-label="Nova linha"
                placeholder="Escreva algo, ou digite “/” para inserir um bloco"
                class="block w-full resize-none overflow-hidden bg-transparent text-[16.5px] leading-[1.68] placeholder:text-muted/70"
              ></textarea>
              {#if menuFor === 'draft'}<InsertMenu onpick={(t, o) => pick(t, null, o)} onclose={() => (menuFor = null)} disabled={ed.can('images') ? [] : ['image']} />{/if}
            </div>
          {/if}
        </div>

        {#if ed.blocks.length === 0 && ed.can('blocks')}
          <div class="mt-6 flex flex-wrap items-center gap-2" role="group" aria-label="Começar com">
            <span class="mr-1 font-mono text-xs text-muted">Começar com</span>
            {#each STARTERS as starter (starter.type)}
              <button
                type="button"
                class="h-9 rounded-full border border-field-line px-3.5 text-sm hover:bg-line/40"
                disabled={starter.type === 'image' && !ed.can('images')}
                onclick={() => pick(starter.type, null)}
              >
                {starter.label}
              </button>
            {/each}
          </div>
        {/if}
      </article>

      </div>
    {/if}
  </main>

  {#if page && !gated && !zen && !wide.current}
    {#if propsOpen}
      <button type="button" class="fixed inset-0 z-40 bg-bg/70" aria-label="Fechar propriedades (fundo)" tabindex="-1" onclick={() => propsDock.closeDrawer()}></button>
      <div class="pointer-events-none fixed inset-y-0 left-0 z-50 flex">
        <div class="animate-slide-left pointer-events-auto w-[min(22rem,80vw)] overflow-y-auto border-r border-line bg-surface p-5">
          <aside aria-label="Propriedades da página" class="flex flex-col gap-5">
            <p class="font-serif text-xl">Propriedades</p>
            <PageProps {ed} onshare={(tab) => ((sharing = tab), propsDock.closeDrawer())} />
          </aside>
        </div>
        <div class="pointer-events-none flex w-14 items-center justify-center">
          <span class="pointer-events-auto"><DockToggle side="left" open label="Fechar propriedades" onclick={() => propsDock.closeDrawer()} /></span>
        </div>
      </div>
    {/if}
    {#if panelOpen}
      <button type="button" class="fixed inset-0 z-40 bg-bg/70" aria-label="Fechar painel (fundo)" tabindex="-1" onclick={() => panel.closeDrawer()}></button>
      <div class="pointer-events-none fixed inset-y-0 right-0 z-50 flex">
        <div class="pointer-events-none flex w-14 items-center justify-center">
          <span class="pointer-events-auto"><DockToggle side="right" open label="Fechar painel" onclick={() => panel.closeDrawer()} /></span>
        </div>
        <div class="animate-slide-right pointer-events-auto w-[min(22rem,80vw)] overflow-y-auto border-l border-line bg-surface p-5">
          <SidePanel {ed} onjump={jump} {onopen} onduplicate={duplicate} />
        </div>
      </div>
    {/if}
    {#if roomForArrows.current && !propsOpen && !panelOpen}
      <DockToggle kind="edge" side="left" open={false} label="Abrir propriedades" onclick={() => propsDock.toggle(false)} />
      <DockToggle kind="edge" side="right" open={false} label="Abrir painel" onclick={() => panel.toggle(false)} />
    {/if}
  {/if}

  {#if fmtField || fmtRich}
    <SelectionToolbar field={fmtField ?? undefined} rich={fmtRich ?? undefined} onerror={(m) => toast.show(m)} />
  {/if}

  {#if zen}
    <div class="animate-fade fixed top-4 right-4 z-40 flex items-center gap-3 rounded-full border border-line bg-surface/90 py-1.5 pr-1.5 pl-4 font-mono text-xs text-muted opacity-60 backdrop-blur-sm transition-opacity focus-within:opacity-100 hover:opacity-100">
      <span data-testid="zen-words">{ed.stats.words} {ed.stats.words === 1 ? 'palavra' : 'palavras'}</span>
      <span class="size-2 rounded-full {ed.save === 'saving' ? 'bg-tag-gold' : 'bg-accent-line'}" role="status" aria-label={ed.save === 'saving' ? 'salvando…' : 'salvo automaticamente'}></span>
      <button type="button" class="h-8 rounded-full border border-field-line px-3 text-fg hover:bg-line/40" onclick={() => (zen = false)}>Sair do zen <span class="text-muted">Esc</span></button>
    </div>
  {/if}

  {#if sharing}
    <ShareModal {ed} bind:tab={sharing} onclose={() => (sharing = null)} />
  {/if}

  {#if deleting && page}
    <ConfirmDialog
      title={permanent ? 'Excluir esta página?' : 'Mover para a lixeira?'}
      body={page.sharedBy
        ? `A página sai da sua lista. Quem a compartilhou (${page.sharedBy}) continua com ela.`
        : permanent
          ? 'Ela será apagada de vez, com todo o conteúdo, e isso não pode ser desfeito.'
          : `A página fica na lixeira por ${ws.settings.retention} dias e pode ser restaurada.`}
      confirmLabel={permanent ? 'Excluir definitivamente' : 'Mover para a lixeira'}
      danger={permanent}
      onconfirm={confirmDelete}
      oncancel={() => (deleting = false)}
    />
  {/if}

  {#if unlocking}
    <VaultPrompt
      target={page?.title ?? 'a página'}
      onunlock={(pw) => {
        if (ws.unlockVault(pw) !== 'ok') return false
        unlocking = false
        return true
      }}
      onclose={() => (unlocking = false)}
    />
  {/if}

  {#if toast.message}
    <div class="fixed bottom-6 left-1/2 z-[80] -translate-x-1/2 rounded-field border border-line bg-surface px-4 py-2 text-sm shadow-lg" role="status">{toast.message}</div>
  {/if}
</div>
