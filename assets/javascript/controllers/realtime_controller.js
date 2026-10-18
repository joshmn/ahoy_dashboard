import { Controller } from "../runtime/controllers.js"
import { getJSON } from "../runtime/fetch.js"
import { compact } from "../runtime/format.js"

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

    if (this.hasToggleTarget) this.toggleTarget.hidden = false

    if (!document.hidden) this.start()
  }

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
      const payload = await getJSON(this.urlValue, { signal: this.pending.signal })
      if (!Number.isFinite(payload.visitors)) return

      this.countTarget.textContent = compact(payload.visitors)
    } catch {
    }
  }
}
