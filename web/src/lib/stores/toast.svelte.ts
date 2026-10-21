const DURATION_MS = 3000

class Toast {
  message = $state('')
  #timer: ReturnType<typeof setTimeout> | undefined

  show(message: string) {
    this.message = message
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => (this.message = ''), DURATION_MS)
  }
}

export const toast = new Toast()
