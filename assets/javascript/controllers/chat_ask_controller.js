import { Controller } from "../runtime/controllers.js"

export default class extends Controller {
  static targets = ["input", "form", "send"]

  connect() {
    this.jump()
    this.take()
    this.grow()
  }

  jump() {
    if (this.element.dataset.chatFresh === "true") return

    const box = this.element.querySelector("[data-chat-scroll]")

    if (box) {
      box.scrollTop = box.scrollHeight
      return
    }

    window.scrollTo({ top: document.documentElement.scrollHeight })
  }

  take() {
    if (!this.hasInputTarget || this.inputTarget.autofocus !== true) return

    this.inputTarget.focus()
  }

  keydown(event) {
    if (!this.hasInputTarget || event.target !== this.inputTarget) return
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
    if (!this.asked) return

    event.preventDefault()
    this.send()
  }

  suggest(event) {
    if (!this.hasInputTarget) return

    event.preventDefault()
    this.inputTarget.value = event.params.question
    this.send()
  }

  grow() {
    if (!this.hasInputTarget) return

    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${this.inputTarget.scrollHeight}px`

    if (this.hasSendTarget) this.sendTarget.disabled = !this.asked
  }

  send() {
    if (!this.hasFormTarget || !this.asked) return

    if (this.hasSendTarget) this.sendTarget.disabled = true
    this.formTarget.requestSubmit()
  }

  get asked() {
    return this.hasInputTarget && this.inputTarget.value.trim() !== ""
  }
}
