import { Controller } from "../runtime/controllers.js"

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
