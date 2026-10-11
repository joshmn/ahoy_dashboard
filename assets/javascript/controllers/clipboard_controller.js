import { Controller } from "../runtime/controllers.js"

// Copies a value to the clipboard and briefly confirms on the button itself.
//
//   <button data-controller="clipboard"
//           data-clipboard-text-value="someone@example.com"
//           data-action="clipboard#copy">Copy</button>
//
// navigator.clipboard only exists in a secure context, which https and
// localhost are and http://portal.lvh.me:5000 is not. So there is a fallback,
// and if both fail the button says so rather than looking like it worked.
export default class extends Controller {
  static values = {
    text: String,
    doneLabel: { type: String, default: "Copied" },
    failedLabel: { type: String, default: "Press ctrl+c" },
    resetAfter: { type: Number, default: 1500 }
  }

  connect() {
    // The button's own label flips to "Copied"; announce that to screen readers.
    this.element.setAttribute("aria-live", "polite")
  }

  async copy(event) {
    event.preventDefault()

    const button = event.currentTarget
    const copied = (await this.viaClipboardApi()) || this.viaSelection()

    this.flash(button, copied ? this.doneLabelValue : this.failedLabelValue)
  }

  async viaClipboardApi() {
    if (!navigator.clipboard) return false

    try {
      await navigator.clipboard.writeText(this.textValue)
      return true
    } catch {
      return false
    }
  }

  // Deprecated, still the only thing that works without a secure context.
  // Leaves the text selected, so ctrl+c is there if even this is blocked.
  viaSelection() {
    const field = document.createElement("textarea")
    field.value = this.textValue
    field.setAttribute("readonly", "")
    field.style.cssText = "position:fixed;top:0;left:0;opacity:0"
    document.body.appendChild(field)

    field.select()
    field.setSelectionRange(0, field.value.length)

    let copied = false
    try {
      copied = document.execCommand("copy")
    } catch {
      copied = false
    }

    document.body.removeChild(field)
    return copied
  }

  flash(button, label) {
    const original = button.dataset.clipboardOriginalLabel || button.textContent
    button.dataset.clipboardOriginalLabel = original
    button.textContent = label

    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => {
      button.textContent = original
    }, this.resetAfterValue)
  }

  disconnect() {
    clearTimeout(this.resetTimer)
  }
}
