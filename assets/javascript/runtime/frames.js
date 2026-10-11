import { FrameQueue } from "./frame_queue.js"

const queue = new FrameQueue(2)
const connected = new Set()
const nearby = typeof IntersectionObserver === "undefined" ? null : new IntersectionObserver((entries) => {
  entries.forEach((entry) => queue.visibility(entry.target, entry.isIntersecting))
}, { rootMargin: "300px" })

const parser = new DOMParser()

const extract = (html, id) => {
  const document = parser.parseFromString(html, "text/html")

  return document.querySelector(`tm-frame#${CSS.escape(id)}`)
}

export class Frame extends HTMLElement {
  static get observedAttributes() {
    return [ "src" ]
  }

  connectedCallback() {
    this.started = true
    connected.add(this)
    this.scheduleInitial()
  }

  disconnectedCallback() {
    this.started = false
    connected.delete(this)
    this.cancel()
  }

  scheduleInitial() {
    if (this.hasAttribute("complete")) {
      queue.complete(this.id)
      return
    }
    if (!this.getAttribute("src")) return

    const lazy = this.getAttribute("loading") === "lazy" && nearby !== null
    queue.add(this, {
      priority: this.dataset.tmPriority === "high" ? 1 : 0,
      after: this.dataset.tmAfter,
      visible: !lazy,
    })
    if (lazy) nearby.observe(this)
  }

  loadInitial() {
    return this.load(this.getAttribute("src"), { automatic: true })
  }

  cancel() {
    queue.cancel(this)
    nearby?.unobserve(this)
    this.pending?.abort()
    this.pending = null
    this.removeAttribute("busy")
    this.removeAttribute("aria-busy")
  }

  attributeChangedCallback(name, before, after) {
    if (name !== "src" || !after || !this.isConnected) return
    if (this.writing || !this.started) return
    if (before === after && this.hasAttribute("complete")) return

    this.load(after)
  }

  reload() {
    const src = this.getAttribute("src")
    if (src) this.load(src)
  }

  async load(url, { remember = false, method = "GET", body = null, automatic = false } = {}) {
    if (!url || !this.isConnected) return null
    if (!automatic) queue.cancel(this)
    nearby?.unobserve(this)
    this.pending?.abort()
    this.pending = new AbortController()

    const request = this.pending

    this.querySelector(":scope > .tm-frame-error")?.remove()
    this.removeAttribute("failed")
    this.setAttribute("busy", "")
    this.setAttribute("aria-busy", "true")

    try {
      const response = await fetch(url, {
        method,
        body,
        headers: { Accept: "text/html, application/xhtml+xml", "Tm-Frame": this.id },
        credentials: "same-origin",
        signal: request.signal
      })
      const html = await response.text()
      if (request.signal.aborted || this.pending !== request || !this.isConnected) return null

      const replacement = extract(html, this.id)
      if (!replacement) throw new Error("The response did not contain this panel")

      this.replaceChildren(...replacement.childNodes)

      if (!response.ok) {
        if (automatic) this.showFailure(url, true)
        return false
      }

      if (remember) this.remember(response.redirected ? response.url : url)

      this.setAttribute("complete", "")
      return true
    } catch (error) {
      if (error.name === "AbortError" || request.signal.aborted || this.pending !== request || !this.isConnected) return null

      if (automatic) this.showFailure(url)
      console.warn("dashboard frame failed", this.id, error)
      return false
    } finally {
      if (this.pending === request) {
        this.removeAttribute("busy")
        this.removeAttribute("aria-busy")
        this.pending = null
        if (!automatic && !request.signal.aborted) queue.complete(this.id)
      }
    }
  }

  showFailure(url, preserve = false) {
    this.setAttribute("failed", "")
    const message = document.createElement("div")
    message.className = "card tm-frame-error"
    message.setAttribute("role", "status")

    const text = document.createElement("p")
    text.textContent = "This panel could not be loaded."
    const retry = document.createElement("button")
    retry.type = "button"
    retry.className = "btn btn-secondary btn-sm"
    retry.textContent = "Try again"
    retry.addEventListener("click", () => this.load(url, { automatic: true }))
    message.append(text, retry)

    if (preserve) {
      this.append(message)
    } else {
      this.replaceChildren(message)
    }
  }

  remember(url) {
    this.writing = true
    this.setAttribute("src", url)
    this.writing = false
  }
}

const frameFor = (element) => {
  const named = element.getAttribute("data-tm-frame")

  if (named === "_top") return null
  if (named) return document.getElementById(named)

  return element.closest("tm-frame")
}

const navigable = (link) => {
  if (link.hasAttribute("download") || link.target) return false
  if (link.origin !== window.location.origin) return false

  return true
}

const onClick = (event) => {
  if (event.defaultPrevented || event.button !== 0) return
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

  const link = event.target instanceof Element ? event.target.closest("a[href]") : null
  if (!link || !navigable(link)) return

  const frame = frameFor(link)
  if (!frame) return

  event.preventDefault()
  frame.load(link.href, { remember: true })
}

const onSubmit = (event) => {
  if (event.defaultPrevented) return

  const form = event.target
  if (!(form instanceof HTMLFormElement)) return

  const frame = frameFor(form)
  if (!frame) return

  const get = (form.method || "get").toLowerCase() === "get"

  // A GET form inside a frame resolves back into it, the way a link does.
  // Anything that writes has to say so: every other form in here is a real
  // navigation with a redirect and a flash behind it, and quietly swallowing
  // those into whichever frame they happened to sit in would break all of them.
  // data-tm-frame is that opt in, and the response is whatever the redirect
  // lands on, read for this frame's id the same as any other load.
  if (!get && !form.hasAttribute("data-tm-frame")) return

  event.preventDefault()

  if (get) {
    const url = new URL(form.action, window.location.href)
    url.search = new URLSearchParams(new FormData(form)).toString()

    frame.load(url.href, { remember: true })
    return
  }

  frame.load(form.action, { method: form.method.toUpperCase(), body: new FormData(form) })
}

export const start = () => {
  if (!customElements.get("tm-frame")) customElements.define("tm-frame", Frame)

  document.addEventListener("click", onClick)
  document.addEventListener("submit", onSubmit)
  window.addEventListener("pagehide", () => {
    queue.pause()
    nearby?.disconnect()
    connected.forEach((frame) => frame.cancel())
  })
  window.addEventListener("pageshow", (event) => {
    if (!event.persisted) return

    queue.resume()
    connected.forEach((frame) => frame.scheduleInitial())
  })
}
