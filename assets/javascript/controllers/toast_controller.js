import { Controller } from "../runtime/controllers.js"

// A flash message, shown once and then gone. It is rendered by the server on
// the page after the action, so nothing has to survive a navigation for it to
// appear, and a reader with the JavaScript off still gets the text.

const SHOW_MS = 2200

export default class extends Controller {
  static values = { delay: { type: Number, default: SHOW_MS } }

  connect() {
    requestAnimationFrame(() => this.element.classList.add("show"))

    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss(event) {
    event?.preventDefault()
    clearTimeout(this.timer)

    this.element.classList.remove("show")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
  }
}
