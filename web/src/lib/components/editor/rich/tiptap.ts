import { Editor, type JSONContent } from '@tiptap/core'
import Bold from '@tiptap/extension-bold'
import Code from '@tiptap/extension-code'
import Document from '@tiptap/extension-document'
import Highlight from '@tiptap/extension-highlight'
import Italic from '@tiptap/extension-italic'
import Link from '@tiptap/extension-link'
import Paragraph from '@tiptap/extension-paragraph'
import Strike from '@tiptap/extension-strike'
import Text from '@tiptap/extension-text'
import Typography from '@tiptap/extension-typography'
import Underline from '@tiptap/extension-underline'
import { CharacterCount, Placeholder, UndoRedo } from '@tiptap/extensions'
import { TextSelection } from '@tiptap/pm/state'
import { safeUrl } from '../../../stores/inline'
import type { RichEngine, RichInstance } from './engine'
import { flattenPaste } from './paste'
import type { MarkKey, Marks, Run } from './runs'

const KEYS: MarkKey[] = ['bold', 'italic', 'underline', 'strike', 'highlight', 'code']

const marksOf = (m: Marks) => [...KEYS.filter((k) => m[k]).map((k) => ({ type: k })), ...(m.link ? [{ type: 'link', attrs: { href: m.link } }] : [])]

const toDoc = (runs: Run[]): JSONContent => ({
  type: 'doc',
  content: [{ type: 'paragraph', content: runs.map((r) => ({ type: 'text', text: r.text, marks: marksOf(r.marks) })) }],
})

export const tiptap: RichEngine = (el, o) => {
  const editor = new Editor({
    element: el,
    // a block is one paragraph: no lists, headings or quotes of its own (those are blocks of the page)
    extensions: [
      Document,
      Paragraph,
      Text,
      Bold,
      Italic,
      Strike,
      Underline,
      Code,
      Highlight,
      // a URL typed with its scheme or "www." becomes a link; "readme.md" does not (.md is a country)
      Link.configure({ openOnClick: false, autolink: true, linkOnPaste: true, defaultProtocol: 'https', isAllowedUri: (url) => !!safeUrl(url), shouldAutoLink: (url) => /^(https?:\/\/|www\.)/i.test(url) }),
      // `->` `<-` `--` `...` `(c)`; the quotes and the rest stay as typed
      Typography.configure({ openDoubleQuote: false, closeDoubleQuote: false, openSingleQuote: false, closeSingleQuote: false, multiplication: false, plusMinus: false, notEqual: false, laquo: false, raquo: false, oneHalf: false, oneQuarter: false, threeQuarters: false, superscriptTwo: false, superscriptThree: false, servicemark: false, trademark: false, registeredTrademark: false }),
      Placeholder.configure({ placeholder: o.placeholder }),
      CharacterCount.configure({ limit: o.maxLength }),
      UndoRedo,
    ],
    content: toDoc(o.runs),
    editable: o.editable,
    parseOptions: { preserveWhitespace: 'full' },
    editorProps: {
      attributes: { role: 'textbox', 'aria-multiline': 'true', 'aria-label': o.label, class: o.className, spellcheck: 'false' },
      transformPasted: (slice, view) => flattenPaste(slice, view.state.schema),
    },
    onUpdate: () => o.onChange(),
    onSelectionUpdate: () => o.onSelection(),
    onBlur: ({ event }) => o.onBlur(event),
  })

  const inst: RichInstance = {
    dom: editor.view.dom as HTMLElement,
    nativePlaceholder: true,
    runs() {
      const out: Run[] = []
      editor.state.doc.firstChild?.forEach((n) => {
        if (!n.isText) return
        const marks: Marks = {}
        for (const m of n.marks) {
          if (m.type.name === 'link') marks.link = m.attrs.href
          else marks[m.type.name as MarkKey] = true
        }
        out.push({ text: n.text ?? '', marks })
      })
      return out
    },
    selection() {
      const { from, to } = editor.state.selection
      return { from: from - 1, to: to - 1 }
    },
    setSelection(from, to) {
      editor.commands.setTextSelection({ from: from + 1, to: to + 1 })
    },
    toggle(mark) {
      const c = editor.chain().focus()
      ;(mark === 'bold' ? c.toggleBold() : mark === 'italic' ? c.toggleItalic() : mark === 'underline' ? c.toggleUnderline() : mark === 'strike' ? c.toggleStrike() : mark === 'highlight' ? c.toggleHighlight() : c.toggleCode()).run()
    },
    setLink(url) {
      if (url) editor.chain().focus().setLink({ href: url }).run()
      else editor.chain().focus().unsetLink().run()
    },
    replace(from, to, runs) {
      editor
        .chain()
        .focus()
        .command(({ tr, state }) => {
          const nodes = runs.filter((r) => r.text).map((r) => state.schema.text(r.text, marksOf(r.marks).map((m) => state.schema.marks[m.type].create('attrs' in m ? m.attrs : undefined))))
          tr.replaceWith(from + 1, to + 1, nodes)
          const end = from + 1 + nodes.reduce((s, n) => s + n.nodeSize, 0)
          tr.setSelection(TextSelection.near(tr.doc.resolve(end)))
          tr.setStoredMarks([])
          return true
        })
        .run()
    },
    focus() {
      editor.commands.focus()
    },
    destroy() {
      editor.destroy()
    },
  }
  return inst
}
