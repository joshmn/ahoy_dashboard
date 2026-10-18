import { CommandDialog, DEBOUNCE_MS } from "../runtime/command_dialog.js"

export default class extends CommandDialog {
  static targets = ["panel", "input", "item", "back"]
  static values = { url: String }

  connect() {
    super.connect()
    this.facet = null
    this.field = null

    this.onOpener = (event) => this.adopt(event)
    document.addEventListener("click", this.onOpener)
  }

  disconnect() {
    super.disconnect()
    document.removeEventListener("click", this.onOpener)
  }

  adopt(event) {
    const opener = event.target.closest?.("[data-tm-pick]")
    if (!opener) return

    event.preventDefault()

    this.field = document.getElementById(opener.dataset.tmPick)
    this.partner = opener.dataset.tmPickDimension
      ? document.getElementById(opener.dataset.tmPickDimension)
      : null

    this.show(opener.dataset.tmPickFacet || null)
  }

  show(facet) {
    if (!this.hasPanelTarget) return

    this.reveal()
    this.inputTarget.value = ""
    this.load(facet)
    this.inputTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    if (!this.isOpen) return

    this.conceal()
    this.field?.focus()
    this.field = null
    this.partner = null
  }

  open(event) {
    event.preventDefault()
    this.inputTarget.value = ""
    this.load(event.currentTarget.dataset.facet || null)
    this.inputTarget.focus()
  }

  choose(event) {
    event.preventDefault()

    const row = event.currentTarget
    const value = row.dataset.value ?? ""

    if (this.field) {
      this.field.value = value
      this.field.dispatchEvent(new Event("input", { bubbles: true }))
      this.field.dispatchEvent(new Event("change", { bubbles: true }))
    }

    const dimension = row.dataset.dimension
    if (this.partner && dimension) {
      this.partner.value = dimension
      this.partner.dispatchEvent(new Event("change", { bubbles: true }))
    }

    this.close()
  }

  search() {
    if (!this.facet) {
      this.filter()
      return
    }

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(this.facet), DEBOUNCE_MS)
  }

  filter() {
    const term = this.inputTarget.value.trim().toLowerCase()

    this.itemTargets.forEach((item) => {
      item.hidden = term.length > 0 && !(item.dataset.term || "").includes(term)
    })

    this.mark(this.visible.length > 0 ? 0 : -1)
  }

  load(facet) {
    const frame = this.element.querySelector("tm-frame")
    if (!frame || !this.hasUrlValue) return

    this.facet = facet || null

    const url = new URL(this.urlValue, window.location.origin)
    if (this.facet) {
      url.searchParams.set("facet", this.facet)
      url.searchParams.set("q", this.inputTarget.value.trim())
    }

    this.inputTarget.placeholder = this.facet ? "Search this list…" : "Pick a facet…"
    if (this.hasBackTarget) this.backTarget.hidden = !this.facet

    this.swap(frame, url.pathname + url.search)
  }

  keyed(event) {
    if (event.key !== "ArrowLeft" || !this.facet || this.inputTarget.selectionStart > 0) return

    event.preventDefault()
    this.inputTarget.value = ""
    this.load(null)
  }
}
