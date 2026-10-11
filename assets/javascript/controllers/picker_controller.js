import { Controller } from "../runtime/controllers.js"

// The value picker, in two steps.
//
// Step one is the facets, step two is one facet's options, and both are the
// server's answer rather than a list held here. Typing does not narrow what is
// on screen by hiding rows: on the facet step there are a dozen and hiding is
// enough, but on the options step the server sent forty out of however many the
// range holds, so a search that only looked at those forty would answer with
// whatever happened to be listed. The facet step filters locally and the options
// step asks again.
//
// What picking does is write into the field that opened the dialog. A row on the
// options step carries both the value and which facet it came from, so choosing
// "United States" under Country can fill in the dimension select beside the
// value input as well as the value itself. That is the whole reason this is not
// the filter dialog: there, a value is added to the filters being built.

const OPEN = "open"
const LOCK = "tm-lock"
const MARKED = "act"
const DEBOUNCE_MS = 220

export default class extends Controller {
  static targets = ["panel", "input", "list", "item", "back"]
  static values = { url: String }

  // Bound on the document because the fields that open this live elsewhere on
  // the form and never pass through this element on the way up.
  connect() {
    this.index = -1
    this.facet = null
    this.field = null

    this.onOpener = (event) => this.adopt(event)
    this.onKey = (event) => this.key(event)

    document.addEventListener("click", this.onOpener)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    clearTimeout(this.timer)
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

  // A control carrying data-tm-pick opens the dialog for the field it names.
  // The field is named rather than found by walking the DOM, so a form can put
  // the button anywhere and two fields can share one button if they ever want
  // to.
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

    this.panelTarget.hidden = false
    this.panelTarget.classList.add(OPEN)
    document.body.classList.add(LOCK)

    this.inputTarget.value = ""
    this.load(facet)
    this.inputTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    if (!this.isOpen) return

    this.panelTarget.hidden = true
    this.panelTarget.classList.remove(OPEN)
    document.body.classList.remove(LOCK)
    this.mark(-1)

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

  // Writing back is the whole point. The value goes into the field, and when the
  // row came from a dimension facet and the opener named a partner select, the
  // dimension goes in beside it: picking a country under Country is picking both
  // halves of that filter, and leaving the select on whatever it said before
  // would save a filter nobody asked for.
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
    // The facet step is a dozen rows the server already sent, so it narrows
    // here. The options step is a window onto something larger and has to ask.
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
      // Back one step rather than out, so the arrow that got you into a facet
      // is the arrow that gets you out of it. Only when nothing is selected in
      // the box, or it would eat the caret.
      case "ArrowLeft":
        if (!this.facet || this.inputTarget.selectionStart > 0) return
        event.preventDefault()
        this.inputTarget.value = ""
        this.load(null)
        break
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
