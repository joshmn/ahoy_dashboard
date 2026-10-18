import { Controller } from "../runtime/controllers.js"

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
