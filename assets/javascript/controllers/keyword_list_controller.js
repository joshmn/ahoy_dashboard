import { Controller } from "../runtime/controllers.js"

// The list you pick an import out of.
//
// Everything it does is local, because everything it works on is already on the
// page: a hundred and fifty rows the server sent in one go. Searching hides
// rows rather than asking again, and sorting reorders the ones that are here.
// That is the opposite of the place picker, and for the opposite reason — there
// the rows on screen are a window onto a quarter of a million, here they are
// the whole list.
//
// Ticking boxes in bulk fires nothing of its own, so it says so on the way out:
// the cost in the corner is worked out by another controller listening for a
// change on the form.

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
        ? `${rows.length} ${rows.length === 1 ? "query" : "queries"}`
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

  // What is on screen, not what exists. Somebody who has searched for "prison"
  // and pressed select all means those, and ticking the hundred rows they
  // cannot see would be the last thing they notice.
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

    // Position is a rank, so smaller is better. Everything else is a count.
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
