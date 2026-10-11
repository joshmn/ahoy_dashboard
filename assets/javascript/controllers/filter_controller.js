import { Controller } from "../runtime/controllers.js"

const ROW = ".tm-filter-row"

export default class extends Controller {
  static targets = ["value", "submit", "blocked"]
  static values = {
    optionsUrl: String,
    delay: { type: Number, default: 200 },
    editing: Boolean,
    removeLabel: { type: String, default: "Remove filter" }
  }

  connect() {
    this.timers = new Map()
    this.requests = new Map()
    this.toggleApply()
  }

  disconnect() {
    this.timers.forEach((timer) => clearTimeout(timer))
    this.requests.forEach((request) => request.abort())
    this.timers.clear()
    this.requests.clear()
  }

  // One controller for the whole form rather than one per row, because the submit
  // reads every row. Which row was typed in comes off the event, and the timers
  // and requests are keyed by it so two rows can be refined at once.
  search(event) {
    this.toggleApply()

    const row = event.target.closest(ROW)
    if (!row) return

    clearTimeout(this.timers.get(row))
    this.timers.set(row, setTimeout(() => this.load(row, event.params.dimension), this.delayValue))
  }

  clear(event) {
    const input = event.target.closest(ROW)?.querySelector("input[list]")
    if (!input) return

    input.value = ""
    input.focus()
    this.toggleApply()
  }

  async load(row, dimension) {
    const input = row.querySelector("input[list]")
    const list = row.querySelector("datalist")
    if (!this.optionsUrlValue || !dimension || !input || !list) return

    this.requests.get(row)?.abort()

    const request = new AbortController()
    this.requests.set(row, request)

    // The url already carries the range, the crawler toggle and the filters
    // already applied, so the values offered are the ones in front of the reader
    // rather than the ones in the default range.
    const url = new URL(this.optionsUrlValue, window.location.origin)
    url.searchParams.set("dimension", dimension)
    url.searchParams.set("q", input.value)

    row.setAttribute("aria-busy", "true")

    const options = await this.fetchOptions(url, request.signal)

    if (this.requests.get(row) === request) row.removeAttribute("aria-busy")

    // A null is a failure, and the values the server rendered are better than
    // none, so the list is left alone.
    if (options) this.render(list, options)
  }

  async fetchOptions(url, signal) {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal })
      if (!response.ok) return null

      const payload = await response.json()

      return Array.isArray(payload.options) ? payload.options : []
    } catch {
      return null
    }
  }

  render(list, options) {
    list.replaceChildren(
      ...options.map((option) => {
        const item = document.createElement("option")
        item.value = option
        return item
      })
    )
  }

  // Every box empty means every row is dropped server side, so the button says so
  // rather than submitting a round trip that changes nothing.
  toggleApply() {
    if (!this.hasSubmitTarget) return

    const empty = this.valueTargets.every((value) => value.value.trim() === "")

    if (this.editingValue) {
      this.label ??= this.submitTarget.textContent
      this.submitTarget.disabled = false
      this.submitTarget.textContent = empty ? this.removeLabelValue : this.label
      if (this.hasBlockedTarget) this.blockedTarget.hidden = true
      return
    }

    this.submitTarget.disabled = empty
    if (this.hasBlockedTarget) this.blockedTarget.hidden = !empty
  }
}
