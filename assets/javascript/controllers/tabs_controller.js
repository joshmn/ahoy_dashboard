import { Controller } from "../runtime/controllers.js"
import { modified, wrap } from "../runtime/keys.js"

export default class extends Controller {
  select(event) {
    const tab = event.currentTarget

    if (modified(event) || event.button > 0) return

    this.tabs.forEach((candidate) => {
      const active = candidate === tab

      candidate.setAttribute("aria-pressed", String(active))

      if (active) {
        candidate.setAttribute("aria-current", "true")
      } else {
        candidate.removeAttribute("aria-current")
      }
    })
  }

  navigate(event) {
    const tabs = this.tabs
    if (!tabs.length) return
    if (event.target.closest(".dropdown")?.querySelector(".dropdown-menu.show")) return

    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key]

    if (step) {
      event.preventDefault()
      const at = tabs.indexOf(document.activeElement)
      const next = at === -1 ? 0 : wrap(at, step, tabs.length)
      tabs[next].focus()
      return
    }

    if (event.key === "Home") {
      event.preventDefault()
      tabs[0].focus()
    } else if (event.key === "End") {
      event.preventDefault()
      tabs[tabs.length - 1].focus()
    }
  }

  get tabs() {
    return Array.from(this.element.querySelectorAll(".nav-link"))
  }
}
