import { Controller } from "../runtime/controllers.js"

// Picking somewhere to search from, by drilling or by typing.
//
// Every panel is the server's answer. Typing does not hide rows: the list is a
// quarter of a million places and the forty on screen are a window onto it, so
// a search that only looked at those forty would answer with whatever happened
// to be listed.
//
// Where it is standing is one parent, not a stack. Going back needs the
// grandparent's code, which the panel's own back button carries, and its label,
// which is the current label with its first part dropped: inside "Illinois,
// United States" the way out is "United States". So nothing has to be
// remembered across loads.

const OPEN = "open"
const LOCK = "tm-lock"
const MARKED = "act"
const DEBOUNCE_MS = 220

const rest = (label) => label.split(",").slice(1).join(",").trim()
const first = (label) => label.split(",")[0].trim()

export default class extends Controller {
  static targets = ["panel", "input", "list", "item", "back"]
  static values = { url: String }

  connect() {
    this.index = -1
    this.row = null
    this.parent = ""
    this.label = ""

    this.onOpener = (event) => this.adopt(event)
    this.onKey = (event) => this.key(event)

    document.addEventListener("click", this.onOpener)
    document.addEventListener("keydown", this.onKey)
  }

  // Nothing announces a frame load, so the first row is marked when the rows
  // arrive. Debounced to the end of the batch, or every row in the new panel
  // would mark itself in turn.
  itemTargetConnected() {
    clearTimeout(this.marker)
    this.marker = setTimeout(() => this.mark(0), 0)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.marker)
    document.removeEventListener("click", this.onOpener)
    document.removeEventListener("keydown", this.onKey)
    document.body.classList.remove(LOCK)
  }

  get isOpen() {
    return this.hasPanelTarget && !this.panelTarget.hidden
  }

  get visible() {
    return this.itemTargets.filter((item) => !item.hidden)
  }

  // A row's own button names the row it fills in. Named rather than found by
  // walking up, because the dialog lives beside the form and not inside the row.
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

    this.panelTarget.hidden = false
    this.panelTarget.classList.add(OPEN)
    document.body.classList.add(LOCK)

    this.inputTarget.value = ""
    this.load(parent, label)
    this.inputTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    if (!this.isOpen) return

    this.panelTarget.hidden = true
    this.panelTarget.classList.remove(OPEN)
    document.body.classList.remove(LOCK)
    this.mark(-1)

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

  // Writing back is the whole point. The two hidden fields are the wire format
  // the form already had, so a place picked here saves exactly as a place typed
  // in by hand does, and the rest is what the row shows and where the next row
  // starts from.
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

    frame.setAttribute("src", url.pathname + url.search)
  }

  mark(position) {
    const items = this.visible
    this.index = items.length === 0 ? -1 : Math.max(0, Math.min(position, items.length - 1))

    this.itemTargets.forEach((item) => {
      item.classList.remove(MARKED)
      item.setAttribute("aria-selected", "false")
    })

    const current = items[this.index]
    if (!current) return

    current.classList.add(MARKED)
    current.setAttribute("aria-selected", "true")
    current.scrollIntoView({ block: "nearest" })
  }

  move(step) {
    const items = this.visible
    if (items.length === 0) return

    this.mark((this.index + step + items.length) % items.length)
  }

  key(event) {
    if (!this.isOpen) return

    switch (event.key) {
      case "Escape":
        event.preventDefault()
        this.close()
        break
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
      case "ArrowDown":
        event.preventDefault()
        this.move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.move(-1)
        break
      case "Enter": {
        const current = this.visible[this.index]
        if (!current) return
        event.preventDefault()
        current.click()
        break
      }
    }
  }
}
