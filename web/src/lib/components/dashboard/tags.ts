import type { TagColor } from '../../stores/workspace.svelte'

// Static strings so Tailwind sees every class.
export const TAG_STYLE: Record<TagColor, { dot: string; chip: string; swatch: string }> = {
  accent: { dot: 'bg-accent-line', chip: 'bg-accent-line/15 text-accent-text', swatch: 'bg-accent-line' },
  rust: { dot: 'bg-tag-rust', chip: 'bg-tag-rust/15 text-tag-rust', swatch: 'bg-tag-rust' },
  blue: { dot: 'bg-tag-blue', chip: 'bg-tag-blue/15 text-tag-blue', swatch: 'bg-tag-blue' },
  gold: { dot: 'bg-tag-gold', chip: 'bg-tag-gold/15 text-tag-gold', swatch: 'bg-tag-gold' },
  plum: { dot: 'bg-tag-plum', chip: 'bg-tag-plum/15 text-tag-plum', swatch: 'bg-tag-plum' },
  teal: { dot: 'bg-tag-teal', chip: 'bg-tag-teal/15 text-tag-teal', swatch: 'bg-tag-teal' },
}

export const COLOR_LABEL: Record<TagColor, string> = {
  accent: 'verde',
  rust: 'terracota',
  blue: 'azul',
  gold: 'dourado',
  plum: 'ameixa',
  teal: 'turquesa',
}
