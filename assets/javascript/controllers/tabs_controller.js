import { Controller } from "../runtime/controllers.js"

export default class extends Controller {
  static values = { frame: String }

  // The tabs are real links inside the card's own frame, so the frame is
  // already the mechanism. This marks the tab pressed straight away rather
  // than leaving it dead until the frame comes back.
  select(event) {
    const tab = event.currentTarget

    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button > 0) return

    // The design marks the tab in front of you with aria-pressed and nothing
    // else. Bootstrap's own .active would be three classes deep and would beat
    // the design's rule, which is how the current tab ended up wearing
    // Bootstrap's pill instead of the design's.
    this.tabs.forEach((candidate) => {
      const active = candidate === tab

      candidate.setAttribute("aria-pressed", String(active))

      if (active) {
        candidate.setAttribute("aria-current", "true")
      } else {
        candidate.removeAttribute("aria-current")
      }
    })

    if (tab.closest("tm-frame")) return

    const frame = this.frame
    const href = tab.getAttribute("href")
    if (!frame || !href) return

    event.preventDefault()

    // A frame that already finished is done and skips the fetch when the src is
    // reassigned, so the completed flag comes off first.
    frame.removeAttribute("complete")
    frame.src = href
  }

  navigate(event) {
    const tabs = this.tabs
    if (!tabs.length) return
    if (event.target.closest(".dropdown")?.querySelector(".dropdown-menu.show")) return

    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key]

    if (step) {
      event.preventDefault()
      const at = tabs.indexOf(document.activeElement)
      const next = at === -1 ? 0 : (at + step + tabs.length) % tabs.length
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

  get frame() {
    if (this.hasFrameValue && this.frameValue) return document.getElementById(this.frameValue)

    return this.element.closest("tm-frame")
  }
}
