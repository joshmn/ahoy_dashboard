import { Controller } from "./controllers.js"
import { wrap } from "./keys.js"

const LOCK = "tm-lock"

const OPEN = "open"

const MARKED = "act"

export const DEBOUNCE_MS = 200

export class CommandDialog extends Controller {
  connect() {
    this.index = -1
    this.onKey = (event) => this.key(event)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("keydown", this.onKey)
    document.body.classList.remove(LOCK)
  }

  get isOpen() {
    return this.hasPanelTarget && !this.panelTarget.hidden
  }

  get visible() {
    return this.itemTargets.filter((item) => !item.hidden)
  }

  reveal() {
    this.panelTarget.hidden = false
    this.panelTarget.classList.add(OPEN)
    document.body.classList.add(LOCK)
  }

  conceal() {
    this.panelTarget.hidden = true
    this.panelTarget.classList.remove(OPEN)
    document.body.classList.remove(LOCK)
    this.mark(-1)
  }

  async swap(frame, url) {
    if (url !== this.loaded) {
      this.loaded = null

      const loaded = await frame.load(url)
      if (loaded === null) return
      if (loaded) this.loaded = url
    }

    this.mark(0)
  }

  mark(position) {
    const items = this.visible
    this.index = items.length === 0 ? -1 : Math.max(0, Math.min(position, items.length - 1))

    this.itemTargets.forEach((item) => {
      item.classList.remove(MARKED)
      item.setAttribute("aria-selected", "false")
    })

    const current = items[this.index]
    this.marked(current)
    if (!current) return

    current.classList.add(MARKED)
    current.setAttribute("aria-selected", "true")
    current.scrollIntoView({ block: "nearest" })
  }

  marked() {}

  move(step) {
    const items = this.visible
    if (items.length === 0) return

    this.mark(wrap(this.index, step, items.length))
  }

  key(event) {
    if (!this.isOpen) return

    switch (event.key) {
      case "Escape":
        event.preventDefault()
        this.close()
        break
      case "ArrowDown":
        event.preventDefault()
        this.move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.move(-1)
        break
      case "Enter": {
        const current = this.visible[this.index]
        if (!current) return
        event.preventDefault()
        current.click()
        break
      }
      default:
        this.keyed(event)
    }
  }

  keyed() {}
}
