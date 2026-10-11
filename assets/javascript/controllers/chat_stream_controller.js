import { Controller } from "../runtime/controllers.js"

// The answer as it is written. It reads an event stream of the row the job is
// filling in and paints the text straight into the turn, so the wait is the
// answer arriving rather than a spinner.
//
// The streamed text is painted as text, never as markup: it is model output and
// it is half written, so there is nothing to render yet. When the stream says
// it is done the frame is reloaded once and the server hands back the same
// answer rendered and sanitised properly.
//
// Falls back to reloading the frame on a timer, which is what this did before
// there was a stream, so a browser with no EventSource still gets the answer.
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

    // The dots are the wait. Once there are words arriving the words are the
    // wait, and three bouncing dots under them are decoration.
    if (this.hasDotsTarget) this.dotsTarget.hidden = Boolean(data.content)

    // Only if they were already at the bottom. Somebody who has scrolled up to
    // read something earlier is reading it, and yanking them back down is worse
    // than letting the answer run on out of sight.
    if (following) this.scroll()
  }

  // The page on the Ask screen, the panel's own box when it is in the panel.
  // Scrolling the window from inside the panel would move the screen the
  // question is about out from under the person reading the answer.
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
    if (tools?.length) return `Read ${tools.join(", ")}`
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
