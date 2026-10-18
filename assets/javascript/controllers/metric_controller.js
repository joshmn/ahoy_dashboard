import { Controller, controllerFor } from "../runtime/controllers.js"
import { getJSON } from "../runtime/fetch.js"
import { modified } from "../runtime/keys.js"

const CHART = '[data-controller~="dash--chart"]'

export default class extends Controller {
  static values = { url: { type: String, default: "" } }

  disconnect() {
    this.pending?.abort()
    this.pending = null
  }

  async select(event) {
    const button = event.currentTarget
    const key = event.params.key || button.value

    if (!key) return
    if (modified(event)) return

    event.preventDefault()

    const params = new URLSearchParams(new FormData(this.element))
    params.set("metric", key)

    const destination = `${this.element.action}?${params}`

    this.pending?.abort()
    this.pending = new AbortController()

    const request = this.pending
    this.element.classList.add("opacity-50")

    try {
      const payload = await this.fetchDashboard(params, request.signal)

      const chart = this.chart
      if (!chart || !chart.update(payload.series, payload.options)) throw new Error("chart unavailable")

      this.paint(payload)
      window.history.replaceState(window.history.state, "", destination)
    } catch (error) {
      if (error.name === "AbortError") return

      window.location.href = destination
    } finally {
      if (!request.signal.aborted) this.element.classList.remove("opacity-50")
    }
  }

  async fetchDashboard(params, signal) {
    const url = new URL(this.urlValue, window.location.origin)
    url.search = params.toString()

    const payload = await getJSON(url, { signal })
    if (!payload || !Array.isArray(payload.series)) throw new Error("malformed payload")

    return payload
  }

  paint(payload) {
    const stats = Array.isArray(payload.stats) ? payload.stats : []

    this.tiles.forEach((tile) => {
      const stat = stats.find((candidate) => candidate.key === tile.value)
      const active = stat ? Boolean(stat.active) : tile.value === payload.metric

      tile.setAttribute("aria-pressed", String(active))

      if (stat) this.paintStat(tile, stat)
    })
  }

  paintStat(tile, stat) {
    const value = tile.querySelector(".tile-value")

    if (value) {
      if (stat.display != null) value.textContent = stat.display
      if (stat.full != null) value.title = stat.full
    }

    this.paintChange(tile, stat)
  }

  paintChange(tile, stat) {
    tile.querySelector(".delta")?.remove()

    const value = tile.querySelector(".tile-value")
    if (stat.delta_html && value) value.insertAdjacentHTML("afterend", ` ${stat.delta_html}`)
  }

  get tiles() {
    return Array.from(this.element.querySelectorAll(".tile"))
  }

  get chart() {
    const element = document.querySelector(CHART)
    if (!element) return null

    return controllerFor(element, "dash--chart")
  }
}
