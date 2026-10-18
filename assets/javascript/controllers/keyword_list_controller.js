import { Controller } from "../runtime/controllers.js"
import { plural } from "../runtime/text.js"

export default class extends Controller {
  static targets = ["search", "row", "body", "shown", "empty", "sort", "clear"]

  connect() {
    this.filter()
  }

  filter() {
    const term = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
    const rows = this.rowTargets
    let shown = 0

    rows.forEach((row) => {
      const hit = !term || (row.dataset.term || "").includes(term)

      row.hidden = !hit
      if (hit) shown += 1
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
    if (this.hasClearTarget) this.clearTarget.hidden = term.length === 0
    if (this.hasShownTarget) {
      this.shownTarget.textContent = shown === rows.length
        ? `${rows.length} ${plural(rows.length, "query", "queries")}`
        : `${shown} of ${rows.length}`
    }
  }

  wipe() {
    if (!this.hasSearchTarget) return

    this.searchTarget.value = ""
    this.filter()
    this.searchTarget.focus()
  }

  all() {
    this.tick(true)
  }

  none() {
    this.tick(false)
  }

  tick(on) {
    this.rowTargets.forEach((row) => {
      if (row.hidden) return

      const box = row.querySelector("input[type='checkbox']")
      if (box) box.checked = on
    })

    this.announce()
  }

  sort(event) {
    const key = event.currentTarget.dataset.key
    if (!key || !this.hasBodyTarget) return

    this.sortTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button === event.currentTarget))
    })

    const sign = key === "position" ? 1 : -1

    this.rowTargets
      .slice()
      .sort((a, b) => sign * (Number(a.dataset[key] || 0) - Number(b.dataset[key] || 0)))
      .forEach((row) => this.bodyTarget.appendChild(row))
  }

  announce() {
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
