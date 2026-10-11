import { Controller } from "../runtime/controllers.js"

const SHOWN = 8
const WILDCARD = "*"
const MAX_PATTERNS = 20
const POOL = 100
const MODAL_KEY = "page-group-matches"

const plural = (count, word) => `${count.toLocaleString("en-US")} ${count === 1 ? word : `${word}s`}`

export default class extends Controller {
  static targets = ["input", "list", "summary", "all", "allTitle"]
  static values = { paths: Array }

  refresh() {
    if (!this.hasInputTarget) return

    const patterns = [...new Set(this.inputTarget.value.split(",").map((pattern) => pattern.trim()).filter(Boolean))].slice(0, MAX_PATTERNS)
    const paths = this.pathsValue
    const matches = patterns.length ? paths.filter(([path]) => patterns.some((pattern) => this.match(String(path), pattern))) : []

    if (this.hasSummaryTarget) this.summaryTarget.textContent = this.summary(paths.length, patterns.length, matches.length)
    if (this.hasListTarget) this.listTarget.replaceChildren(...this.rows(matches))
    if (this.hasAllTarget) this.allTarget.replaceChildren(...matches.map(([path, visitors]) => this.row(path, visitors)))
    if (this.hasAllTitleTarget) this.allTitleTarget.textContent = this.title(matches.length)
  }

  match(path, pattern) {
    if (!pattern.endsWith(WILDCARD)) return path === pattern

    const prefix = pattern.slice(0, -1)
    return prefix.length > 0 && path.startsWith(prefix)
  }

  summary(total, patterns, matched) {
    if (total === 0) return "No page views in the last 30 days to check against."
    if (patterns === 0) return "Type a pattern to see which pages it groups."

    const pool = total >= POOL
      ? `the ${POOL} most visited pages in the last 30 days`
      : `${total} ${total === 1 ? "page" : "pages"} visited in the last 30 days`

    return `Matches ${matched === 0 ? "none" : matched} of ${pool}.`
  }

  title(matched) {
    return `All ${matched} ${matched === 1 ? "page" : "pages"} it groups`
  }

  rows(matches) {
    const rows = matches.slice(0, SHOWN).map(([path, visitors]) => this.row(path, visitors))

    if (matches.length > SHOWN) rows.push(this.moreRow(matches.length - SHOWN))

    return rows
  }

  row(path, visitors) {
    const row = document.createElement("li")
    const name = document.createElement("span")
    const count = document.createElement("span")

    name.className = "grp-path"
    name.textContent = path
    count.className = "grp-count"
    count.textContent = plural(Number(visitors) || 0, "visitor")
    row.append(name, count)

    return row
  }

  // The same button the server renders. The action is read off the element when
  // the click happens, so a row built here opens the dialog without any wiring.
  moreRow(rest) {
    const row = document.createElement("li")
    const button = document.createElement("button")

    row.className = "grp-more"
    button.type = "button"
    button.className = "btn btn-link btn-sm grp-more-open"
    button.textContent = `and ${rest.toLocaleString("en-US")} more`
    button.setAttribute("aria-haspopup", "dialog")
    button.setAttribute("data-action", "dash--modal#open")
    button.setAttribute("data-dash--modal-key-param", MODAL_KEY)
    row.append(button)

    return row
  }
}
