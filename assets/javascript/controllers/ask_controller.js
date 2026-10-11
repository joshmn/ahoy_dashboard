import { Controller } from "../runtime/controllers.js"

export default class extends Controller {
  static targets = ["panel", "opener"]
  static values = { url: String }

  toggle(event) {
    if (!this.hasPanelTarget) return

    event.preventDefault()

    if (this.open) {
      this.close()
    } else {
      this.show()
    }
  }

  show() {
    this.stamp(true)
    this.frame?.load(this.current)
  }

  close(event) {
    event?.preventDefault()
    if (!this.hasPanelTarget || !this.open) return

    this.stamp(false)
    this.forget()
    this.openerTarget?.focus()
  }

  key(event) {
    if (event.key !== "Escape" || event.isComposing) return

    this.close(event)
  }

  stamp(open) {
    const root = document.documentElement

    root.setAttribute("data-ask-live", "")
    root.setAttribute("data-ask", open ? "open" : "shut")

    this.panelTarget.hidden = !open
    this.openerTarget?.setAttribute("aria-expanded", String(open))
  }

  forget() {
    const token = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.urlValue, {
      method: "DELETE",
      headers: token ? { "X-CSRF-Token": token } : {},
      credentials: "same-origin",
      keepalive: true
    }).catch(() => {})
  }

  get open() {
    return document.documentElement.getAttribute("data-ask") === "open"
  }

  get frame() {
    return this.panelTarget.querySelector("tm-frame")
  }

  get current() {
    const held = this.panelTarget.querySelector("[data-ask-url]")?.getAttribute("data-ask-url")

    return held || this.openerTarget?.href
  }
}
