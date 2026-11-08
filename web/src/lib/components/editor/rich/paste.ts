import { Fragment, Slice, type Node, type Schema } from '@tiptap/pm/model'

/**
 * A block is one paragraph: whatever is pasted (several paragraphs, lists, a table from a page) becomes that paragraph's
 * text, one line per original block, keeping only the marks the schema knows. Used by the ProseMirror-based engines.
 */
export function flattenPaste(slice: Slice, schema: Schema): Slice {
  const first = slice.content.firstChild
  if (!first || first.isInline) return slice
  const out: Node[] = []
  let started = false
  slice.content.descendants((node) => {
    if (!node.isTextblock) return true
    if (started) out.push(schema.text('\n'))
    started = true
    node.content.forEach((c) => {
      if (c.isText && c.text) out.push(schema.text(c.text, c.marks.filter((m) => m.type.name in schema.marks)))
    })
    return false
  })
  return new Slice(Fragment.from(out), 0, 0)
}
