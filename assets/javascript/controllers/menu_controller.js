import { Controller } from "../runtime/controllers.js"

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

    // Nothing is marked and nothing is focused on open, the way the design
    // opens it. The first arrow key moves to the top of the list from here, so
    // a keyboard still has a way in without the panel pre-answering.
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

    // An item that opens a dialog hands over rather than staying up behind it.
    // Everything else inside the menu leaves it alone, which is what lets a
    // click land on a link without the menu closing under the pointer first.
    if (this.element.contains(event.target)) {
      if (event.target.closest?.('[aria-haspopup="dialog"]')) this.close()
      return
    }

    this.close()
  }

  // The pointer and the arrow keys share one cursor, so arrowing down off a row
  // the pointer happens to be resting on goes to the row under it rather than
  // back to wherever the keys had got to.
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
      const at = this.at
      this.move(at === -1 ? (step > 0 ? 0 : items.length - 1) : (at + step + items.length) % items.length)
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

  // Read off the element rather than held as a number, so a panel that swapped
  // its own contents for the next step starts the keys at the top again instead
  // of carrying an index into a list that is not the same list.
  get at() {
    return this.current ? this.items.indexOf(this.current) : -1
  }

  // The menu helpers render their items as plain .menu-item elements with no
  // target attribute, so the class is what there is to go on. An
  // explicit item target still wins where a panel wants to name its own.
  get items() {
    const found = this.hasItemTarget ? this.itemTargets : Array.from(this.container.querySelectorAll(".menu-item"))

    return found.filter((item) => !item.disabled && item.getClientRects().length > 0)
  }

  // Not named scope: Stimulus owns this.scope, and reading a target from a
  // getter of that name recurses through its own target lookup until the stack
  // gives out.
  get container() {
    return this.hasPanelTarget ? this.panelTarget : this.element
  }
}
