import { CommandDialog, DEBOUNCE_MS } from "../runtime/command_dialog.js"

const rest = (label) => label.split(",").slice(1).join(",").trim()
const first = (label) => label.split(",")[0].trim()

export default class extends CommandDialog {
  static targets = ["panel", "input", "item", "back"]
  static values = { url: String }

  connect() {
    super.connect()
    this.row = null
    this.parent = ""
    this.label = ""

    this.onOpener = (event) => this.adopt(event)
    document.addEventListener("click", this.onOpener)
  }

  disconnect() {
    super.disconnect()
    document.removeEventListener("click", this.onOpener)
  }

  adopt(event) {
    const opener = event.target.closest?.("[data-tm-place]")
    if (!opener) return

    event.preventDefault()

    this.row = document.getElementById(opener.dataset.tmPlace)
    if (!this.row) return

    this.show(this.row.dataset.placeParent || "", this.row.dataset.placeParentLabel || "")
  }

  show(parent, label) {
    if (!this.hasPanelTarget) return

    this.reveal()
    this.inputTarget.value = ""
    this.load(parent, label)
    this.inputTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    if (!this.isOpen) return

    this.conceal()
    this.row?.querySelector("[data-tm-place]")?.focus()
    this.row = null
  }

  into(event) {
    event.preventDefault()
    this.inputTarget.value = ""
    this.load(event.currentTarget.dataset.parent || "", event.currentTarget.dataset.label || "")
    this.inputTarget.focus()
  }

  up(event) {
    event.preventDefault()
    this.back()
  }

  back() {
    this.inputTarget.value = ""
    this.load(this.element.querySelector(".pop-hd [data-parent]")?.dataset.parent || "", rest(this.label))
    this.inputTarget.focus()
  }

  choose(event) {
    event.preventDefault()
    if (!this.row) return

    const picked = event.currentTarget
    const country = this.field(this.row, "place_countries")
    const city = this.field(this.row, "place_cities")

    if (country) country.value = picked.dataset.country || ""
    if (city) city.value = picked.dataset.name || ""

    this.row.dataset.placeCode = picked.dataset.code || ""
    this.row.dataset.placeParent = picked.dataset.parent || ""
    this.row.dataset.placeParentLabel = picked.dataset.parentLabel || ""
    this.row.dataset.placeName = picked.dataset.label || ""

    country?.dispatchEvent(new Event("change", { bubbles: true }))

    this.close()
  }

  field(row, name) {
    return row.querySelector(`[name$="[${name}][]"]`)
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(this.parent, this.label), DEBOUNCE_MS)
  }

  load(parent, label) {
    const frame = this.element.querySelector("tm-frame")
    if (!frame || !this.hasUrlValue) return

    this.parent = parent || ""
    this.label = label || ""

    const url = new URL(this.urlValue, window.location.origin)
    if (this.parent) url.searchParams.set("parent", this.parent)
    const term = this.inputTarget.value.trim()
    if (term) url.searchParams.set("q", term)

    this.inputTarget.placeholder = this.label ? `Search inside ${first(this.label)}…` : "Pick a country…"
    if (this.hasBackTarget) this.backTarget.hidden = !this.parent

    this.swap(frame, url.pathname + url.search)
  }

  keyed(event) {
    switch (event.key) {
      case "ArrowLeft":
        if (!this.parent || this.inputTarget.selectionStart > 0) return
        event.preventDefault()
        this.back()
        break
      case "ArrowRight": {
        if (this.inputTarget.selectionStart < this.inputTarget.value.length) return
        const open = this.visible[this.index]?.parentElement.querySelector("[data-action*='into']")
        if (!open) return
        event.preventDefault()
        open.click()
        break
      }
    }
  }
}
