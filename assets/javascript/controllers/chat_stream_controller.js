import { Controller } from "../runtime/controllers.js"
import { sentence } from "../runtime/text.js"

export default class extends Controller {
  static targets = ["body", "dots", "label"]
  static values = {
    url: String,
    frame: String,
    interval: { type: Number, default: 1000 }
  }

  connect() {
    if (typeof EventSource === "undefined") return this.fallback()

    this.open()
  }

  disconnect() {
    this.source?.close()
    this.source = null
    clearTimeout(this.timer)
    this.timer = null
  }

  open() {
    this.source = new EventSource(this.urlValue)

    this.source.addEventListener("tick", (event) => this.paint(event))
    this.source.addEventListener("done", (event) => {
      this.paint(event)
      this.source?.close()
      this.source = null
      this.reload()
    })

    this.source.onerror = () => {
      this.source?.close()
      this.source = null
      this.fallback()
    }
  }

  paint(event) {
    let data

    try {
      data = JSON.parse(event.data)
    } catch {
      return
    }

    const following = this.atBottom()

    if (this.hasBodyTarget && data.content) this.bodyTarget.textContent = data.content
    if (this.hasLabelTarget) this.labelTarget.textContent = this.label(data)

    if (this.hasDotsTarget) this.dotsTarget.hidden = Boolean(data.content)

    if (following) this.scroll()
  }

  get box() {
    return this.element.closest("[data-chat-scroll]")
  }

  atBottom() {
    const box = this.box

    if (box) return box.scrollHeight - box.clientHeight - box.scrollTop < 120

    return document.documentElement.scrollHeight - window.innerHeight - window.scrollY < 120
  }

  scroll() {
    const box = this.box

    if (box) {
      box.scrollTo({ top: box.scrollHeight, behavior: "smooth" })
      return
    }

    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "smooth" })
  }

  label({ content, tools }) {
    if (tools?.length) return `Read ${sentence(tools)}`
    if (content) return "Writing"

    return "Reading the data"
  }

  fallback() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.reload(), this.intervalValue)
  }

  reload() {
    if (document.hidden) return this.fallback()

    document.getElementById(this.frameValue)?.reload?.()
  }
}
