import { Controller } from "../runtime/controllers.js"

// The composer. It sits above the form rather than on it, because the three
// questions in an empty thread submit it too and they are the other side of the
// panel from the box you type in.
//
// Enter sends, shift and enter writes a line. A textarea is the right control
// because an answer can be a paragraph long, but a textarea that needs the mouse
// to send does not read as a conversation.
export default class extends Controller {
  static targets = ["input", "form", "send"]

  connect() {
    this.jump()
    this.take()
    this.grow()
  }

  // The panel's thread scrolls inside its own box, and taking the window to the
  // bottom from there would move the page the question is about.
  jump() {
    if (this.element.dataset.chatFresh === "true") return

    const box = this.element.querySelector("[data-chat-scroll]")

    if (box) {
      box.scrollTop = box.scrollHeight
      return
    }

    window.scrollTo({ top: document.documentElement.scrollHeight })
  }

  // autofocus fires once, at page load. In the panel the whole composer is
  // rendered again after every answer, so without this the caret is nowhere
  // after the first question.
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

  // One row until there is more than one, up to the cap the stylesheet sets, so
  // a one line question does not sit in a box built for a paragraph and a long
  // one is not read through a slot.
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
