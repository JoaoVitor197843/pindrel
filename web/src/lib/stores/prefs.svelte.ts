// Per-person editor preferences (kept in this browser only; nothing here belongs on the server).
const KEY = 'pindrel:editor-prefs'

export type IconAlign = 'left' | 'center'

class EditorPrefs {
  iconAlign = $state<IconAlign>('left')
  /** The icons chosen most recently, newest first. */
  recentIcons = $state<string[]>([])
  /** Panel and property sections the person folded. */
  folded = $state<string[]>([])

  constructor() {
    try {
      const raw = JSON.parse(localStorage.getItem(KEY) ?? '{}')
      if (raw.iconAlign === 'center') this.iconAlign = 'center'
      if (Array.isArray(raw.recentIcons)) this.recentIcons = raw.recentIcons.filter((s: unknown) => typeof s === 'string').slice(0, 12)
      if (Array.isArray(raw.folded)) this.folded = raw.folded.filter((s: unknown) => typeof s === 'string').slice(0, 20)
    } catch {
      // nothing stored, or storage is blocked: defaults
    }
  }

  #save() {
    try {
      localStorage.setItem(KEY, JSON.stringify({ iconAlign: this.iconAlign, recentIcons: this.recentIcons, folded: this.folded }))
    } catch {
      // not remembered; still works for this visit
    }
  }

  setIconAlign(align: IconAlign) {
    this.iconAlign = align
    this.#save()
  }

  isFolded(section: string) {
    return this.folded.includes(section)
  }

  toggleFold(section: string) {
    this.folded = this.isFolded(section) ? this.folded.filter((s) => s !== section) : [...this.folded, section]
    this.#save()
  }

  rememberIcon(icon: string) {
    this.recentIcons = [icon, ...this.recentIcons.filter((i) => i !== icon)].slice(0, 12)
    this.#save()
  }
}

export const prefs = new EditorPrefs()
