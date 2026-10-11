import { Controller } from "../runtime/controllers.js"

const UNITS = [[1e9, "B"], [1e6, "M"], [1e3, "k"]]

// Two jobs off one timer: the header pill, which reads a number out of JSON, and
// the realtime page, which reloads a frame. Which one depends on whether the
// element names a frame.
export default class extends Controller {
  static targets = ["count", "toggle"]
  static values = {
    url: { type: String, default: "" },
    frame: String,
    interval: { type: Number, default: 15000 },
    pauseText: String,
    resumeText: String
  }

  connect() {
    this.paused = false
    this.onVisibility = () => this.visibility()
    document.addEventListener("visibilitychange", this.onVisibility)

    // With no JavaScript there is no refreshing to pause, so the control ships
    // hidden and only this reveals it.
    if (this.hasToggleTarget) this.toggleTarget.hidden = false

    if (!document.hidden) this.start()
  }

  // A frame swap can take the pill out from under this, so an interval left
  // running here polls against an element that is no longer on screen.
  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  start({ immediate = false } = {}) {
    if (this.timer) return

    this.timer = setInterval(() => this.poll(), this.intervalValue)
    if (immediate) this.poll()
  }

  stop() {
    clearInterval(this.timer)
    this.timer = null
    this.pending?.abort()
    this.pending = null
  }

  toggle() {
    this.paused = !this.paused

    if (this.paused) {
      this.stop()
    } else {
      this.start({ immediate: true })
    }

    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = this.paused ? this.resumeTextValue : this.pauseTextValue
    }
  }

  visibility() {
    if (document.hidden) {
      this.stop()
    } else if (!this.paused) {
      this.start({ immediate: true })
    }
  }

  poll() {
    if (this.hasFrameValue) return this.refresh()

    return this.count()
  }

  refresh() {
    document.getElementById(this.frameValue)?.reload()
  }

  async count() {
    if (!this.urlValue || !this.hasCountTarget) return

    this.pending?.abort()
    this.pending = new AbortController()

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        signal: this.pending.signal
      })
      if (!response.ok) return

      const payload = await response.json()
      if (typeof payload.visitors !== "number") return

      this.countTarget.textContent = this.compact(payload.visitors)
    } catch {
      // A dropped poll is not worth saying anything about. The next one is
      // fifteen seconds away and the number on screen is still roughly right.
    }
  }

  // Matches AhoyDashboard::DashboardHelper.compact_number, so a refreshed count reads the
  // same as the one the server rendered.
  compact(value) {
    const number = Number(value)
    if (!Number.isFinite(number)) return "0"

    for (const [threshold, suffix] of UNITS) {
      if (Math.abs(number) < threshold) continue

      const scaled = Math.round((number / threshold) * 10) / 10

      return `${Number.isInteger(scaled) ? scaled : scaled.toFixed(1)}${suffix}`
    }

    return String(Math.round(number))
  }
}
