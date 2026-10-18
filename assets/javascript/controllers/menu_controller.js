import { Controller } from "../runtime/controllers.js"
import { wrap } from "../runtime/keys.js"

export default class extends Controller {
  static targets = ["button", "panel", "item"]

  connect() {
    this.onDocumentClick = (event) => this.dismiss(event)
    this.onDocumentKey = (event) => this.key(event)
    this.onPointerOver = (event) => this.track(event)

    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onDocumentKey)
    this.element.addEventListener("pointerover", this.onPointerOver)

    this.sync()
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onDocumentKey)
    this.element.removeEventListener("pointerover", this.onPointerOver)
  }

  toggle(event) {
    event.preventDefault()

    if (this.open) {
      this.close({ restoreFocus: true })
    } else {
      this.show()
    }
  }

  show() {
    if (this.open) return

    this.container.classList.add("show")
    this.sync()

    this.mark(null)
  }

  close({ restoreFocus = false } = {}) {
    if (!this.open) return

    this.container.classList.remove("show")
    this.mark(null)
    this.sync()

    if (restoreFocus && this.hasButtonTarget) this.buttonTarget.focus()
  }

  dismiss(event) {
    if (!this.open) return

    if (this.element.contains(event.target)) {
      if (event.target.closest?.('[aria-haspopup="dialog"]')) this.close()
      return
    }

    this.close()
  }

  track(event) {
    if (!this.open) return

    const item = event.target.closest?.(".menu-item")
    if (item && this.items.includes(item)) this.mark(item)
  }

  key(event) {
    if (!this.open) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close({ restoreFocus: true })
      return
    }

    const items = this.items
    if (!items.length) return

    const step = { ArrowDown: 1, ArrowUp: -1 }[event.key]

    if (step) {
      event.preventDefault()
      this.move(wrap(this.at, step, items.length))
      return
    }

    if (event.key === "Home") {
      event.preventDefault()
      this.move(0)
    } else if (event.key === "End") {
      event.preventDefault()
      this.move(items.length - 1)
    }
  }

  move(index) {
    const item = this.items[index]
    if (!item) return

    this.mark(item)
    item.focus()

    item.scrollIntoView({ block: "nearest" })
  }

  mark(item) {
    this.items.forEach((each) => each.classList.toggle("act", each === item))
    this.current = item
  }

  sync() {
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", String(this.open))
  }

  get open() {
    return this.container.classList.contains("show")
  }

  get at() {
    return this.current ? this.items.indexOf(this.current) : -1
  }

  get items() {
    const found = this.hasItemTarget ? this.itemTargets : Array.from(this.container.querySelectorAll(".menu-item"))

    return found.filter((item) => !item.disabled && item.getClientRects().length > 0)
  }

  get container() {
    return this.hasPanelTarget ? this.panelTarget : this.element
  }
}
