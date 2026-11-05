import type { TextEdit } from '../../stores/inline'

/**
 * Writes an edit through the field itself, so the component that owns it updates its state the usual way, then puts
 * the selection back on the changed words.
 */
export function applyEdit(field: HTMLTextAreaElement, edit: TextEdit | null): boolean {
  if (!edit) return false
  field.value = edit.text
  field.dispatchEvent(new Event('input', { bubbles: true }))
  field.focus()
  field.setSelectionRange(edit.start, edit.end)
  return true
}
