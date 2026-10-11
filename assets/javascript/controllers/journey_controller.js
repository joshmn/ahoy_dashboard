import { Controller } from "../runtime/controllers.js"

// Keeps the newest column in view.
//
// Following a step renders one more column on the right, and on a chain three
// or four deep that column arrives off screen. Nothing else on the page needs
// this, because nothing else on the page grows sideways.

export default class extends Controller {
  connect() {
    if (this.element.scrollWidth <= this.element.clientWidth) return

    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    const columns = this.element.querySelectorAll(".j-col")
    const newest = columns[columns.length - 1]
    if (!newest) return

    requestAnimationFrame(() => {
      const edge = newest.getBoundingClientRect().right - this.element.getBoundingClientRect().right
      if (edge <= 0) return

      this.element.scrollTo({ left: this.element.scrollLeft + edge, behavior: still ? "auto" : "smooth" })
    })
  }
}
