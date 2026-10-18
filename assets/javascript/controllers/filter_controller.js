import { Controller } from "../runtime/controllers.js"
import { getJSON } from "../runtime/fetch.js"

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

    const url = new URL(this.optionsUrlValue, window.location.origin)
    url.searchParams.set("dimension", dimension)
    url.searchParams.set("q", input.value)

    row.setAttribute("aria-busy", "true")

    const options = await this.fetchOptions(url, request.signal)

    if (this.requests.get(row) === request) row.removeAttribute("aria-busy")

    if (options) this.render(list, options)
  }

  async fetchOptions(url, signal) {
    try {
      const payload = await getJSON(url, { signal })

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
