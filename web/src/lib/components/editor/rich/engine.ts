// The contract between the page and its rich-text editor (TipTap). The page never talks to TipTap directly: only the block that has the focus gets one, loaded when it is first needed, and it is thrown away
// on blur. Offsets are positions in the plain text (no markers), so every engine counts the same way.
import type { MarkKey, Run } from './runs'

export interface RichOptions {
  runs: Run[]
  editable: boolean
  /** Accessible name and the CSS classes of the editable element. */
  label: string
  className: string
  /** Shown while the block is empty, by engines that can draw it themselves. */
  placeholder: string
  /** Most characters the block takes (what a plain field's maxlength did). */
  maxLength: number
  /** The document changed. */
  onChange: () => void
  /** The caret or the selection moved. */
  onSelection: () => void
  onBlur: (e: FocusEvent) => void
}

export interface RichInstance {
  /** The editable element, for focus checks. */
  readonly dom: HTMLElement
  /** True when the engine draws the placeholder itself; the field draws one for the others. */
  readonly nativePlaceholder: boolean
  runs(): Run[]
  selection(): { from: number; to: number }
  setSelection(from: number, to: number): void
  toggle(mark: MarkKey): void
  /** Links the selection, or takes the link off with null. */
  setLink(url: string | null): void
  /** Swaps a range for runs, puts the caret after them and makes the next typed letters plain. */
  replace(from: number, to: number, runs: Run[]): void
  focus(): void
  destroy(): void
}

export type RichEngine = (el: HTMLElement, opts: RichOptions) => RichInstance

let loaded: Promise<RichEngine> | undefined

/** Loads the editor the first time a block is focused; a page that is only read never downloads it. */
export function loadEngine(): Promise<RichEngine> {
  if (!loaded) {
    loaded = import('./tiptap').then((m) => m.tiptap)
    loaded.catch(() => (loaded = undefined))
  }
  return loaded
}

/**
 * Brings the editor in while the connection is still there: the first focus would otherwise need the network at the
 * moment the person starts to write, and a page opened offline could not be edited. Runs when the browser is idle and
 * is a no-op when the editor is already loaded or cannot load.
 */
export function prefetchEngine() {
  if (loaded || typeof window === 'undefined') return
  const run = () => void loadEngine().catch(() => {})
  if ('requestIdleCallback' in window) window.requestIdleCallback(run, { timeout: 4000 })
  else setTimeout(run, 1500)
}

/** The live editor instance of an editable element, so the selection toolbar can reach it. */
export const instances = new WeakMap<Element, RichInstance>()

/**
 * True while the formatting bar is asking for a link address: the address field takes the focus away from the text, and
 * the text must stay open (and keep its selection) until the person is done.
 */
export const barLock = { linking: false }
