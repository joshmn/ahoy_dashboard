import { Controller } from "../runtime/controllers.js"

const LOCK = "tm-lock"

// The design draws the palette as display:none and opens it with a class, so
// the hidden attribute alone cannot show it: a class rule beats the user agent's
// [hidden]. Both are set. The attribute is what keeps it out of the tab order
// and out of the accessibility tree while it is shut; the class is what makes it
// visible.
const OPEN = "open"

// The design marks the row the arrow keys are on with .act, not .active.
const MARKED = "act"

const DEBOUNCE_MS = 200
const MINIMUM_TERM = 2
const SHAPE = "palette"

export default class extends Controller {
  static targets = ["panel", "input", "list", "item", "group", "none", "found", "status", "commands", "loading", "failure"]

  // The shortcut is bound here rather than through data-action, because the
  // runtime dispatches by walking up from the event target and a keystroke
  // landing on the body never passes through this element.
  connect() {
    this.index = -1
    this.onKey = (event) => this.key(event)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    this.cancel()
    this.commandsRequest?.abort()
    document.removeEventListener("keydown", this.onKey)
    document.body.classList.remove(LOCK)
  }

  get open() {
    return this.hasPanelTarget && !this.panelTarget.hidden
  }

  get visible() {
    return this.itemTargets.filter((item) => !item.hidden)
  }

  toggle(event) {
    if (event && (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)) return

    event?.preventDefault()
    this.open ? this.close() : this.show()
  }

  show() {
    if (!this.hasPanelTarget) return

    this.returnTo = document.activeElement
    this.panelTarget.hidden = false
    this.panelTarget.classList.add(OPEN)
    document.body.classList.add(LOCK)
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
    this.loadCommands()
  }

  async loadCommands() {
    if (this.commandsLoaded || this.commandsRequest) return

    const request = new AbortController()
    this.commandsRequest = request
    this.commandsTarget.setAttribute("aria-busy", "true")
    this.loadingTarget.hidden = false
    this.failureTarget.hidden = true

    try {
      const response = await fetch(this.panelTarget.dataset.commandsUrl, {
        signal: request.signal,
        credentials: "same-origin",
        headers: { Accept: "text/html", "Tm-Frame": "tm-palette-commands" },
      })
      if (!response.ok || response.redirected) throw new Error("Commands could not be loaded")

      const html = await response.text()
      const focused = document.activeElement
      this.commandsTarget.innerHTML = html
      this.commandsLoaded = true
      if (this.open) {
        this.filter()
        if (!focused.isConnected) this.inputTarget.focus()
      }
    } catch (error) {
      if (error.name !== "AbortError") {
        this.loadingTarget.hidden = true
        this.failureTarget.hidden = false
      }
    } finally {
      this.commandsRequest = null
      this.commandsTarget.setAttribute("aria-busy", "false")
    }
  }

  close(event) {
    event?.preventDefault()
    if (!this.open) return

    this.cancel()
    this.panelTarget.hidden = true
    this.panelTarget.classList.remove(OPEN)
    document.body.classList.remove(LOCK)
    this.mark(-1)

    const target = this.returnTo
    this.returnTo = null
    if (target && target !== document.body && target.isConnected) target.focus()
  }

  filter() {
    const term = this.inputTarget.value.trim().toLowerCase()

    this.itemTargets.forEach((item) => {
      item.hidden = term.length > 0 && !item.dataset.term.includes(term)
    })

    // A heading with nothing under it is a heading for nothing.
    this.groupTargets.forEach((group) => {
      group.hidden = group.querySelectorAll("[data-dash--palette-target~='item']:not([hidden])").length === 0
    })

    this.seek(term)
    this.settle(0)
  }

  get searchUrl() {
    return this.hasPanelTarget ? this.panelTarget.dataset.searchUrl : null
  }

  cancel() {
    clearTimeout(this.timer)
    this.request?.abort()
    this.request = null
    this.searching = false
  }

  seek(term) {
    this.cancel()
    if (!this.hasFoundTarget) return

    if (term.length < MINIMUM_TERM || !this.searchUrl) {
      this.foundTarget.replaceChildren()
      return
    }

    this.searching = true
    this.foundTarget.setAttribute("aria-busy", "true")
    this.timer = setTimeout(() => this.load(term), DEBOUNCE_MS)
  }

  async load(term) {
    const request = new AbortController()
    this.request = request

    const url = new URL(this.searchUrl, window.location.origin)
    url.searchParams.set("q", term)
    url.searchParams.set("shape", SHAPE)

    let html = ""

    try {
      const response = await fetch(url, {
        signal: request.signal,
        credentials: "same-origin",
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" },
      })
      if (response.ok) html = await response.text()
    } catch (error) {
      if (error.name === "AbortError") return
    }

    if (this.request !== request) return

    const kept = this.visible[this.index]
    this.request = null
    this.searching = false
    this.foundTarget.innerHTML = html
    this.foundTarget.setAttribute("aria-busy", "false")
    this.settle(kept && !kept.dataset.found ? this.visible.indexOf(kept) : 0)
  }

  settle(position) {
    const term = this.inputTarget.value.trim()
    const items = this.visible
    const values = items.filter((item) => item.dataset.found).length
    const commands = items.length - values

    if (this.hasNoneTarget) {
      const none = this.noneTarget
      none.hidden = items.length > 0 || !this.commandsLoaded
      none.textContent = this.searching
        ? none.dataset.searching
        : term.length < MINIMUM_TERM ? none.dataset.short : none.dataset.empty
    }

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = this.searching || term.length === 0
        ? ""
        : `${commands} ${commands === 1 ? "command" : "commands"}, ${values} ${values === 1 ? "value" : "values"} to filter by`
    }

    this.mark(items.length > 0 ? position : -1)
  }

  mark(position) {
    const items = this.visible
    this.index = items.length === 0 ? -1 : Math.max(0, Math.min(position, items.length - 1))

    this.itemTargets.forEach((item) => {
      item.classList.remove(MARKED)
      item.setAttribute("aria-selected", "false")
    })

    const current = items[this.index]
    if (!current) {
      this.inputTarget.removeAttribute("aria-activedescendant")
      return
    }

    if (!current.id) current.id = `tm-palette-option-${(this.minted = (this.minted || 0) + 1)}`

    current.classList.add(MARKED)
    current.setAttribute("aria-selected", "true")
    this.inputTarget.setAttribute("aria-activedescendant", current.id)
    current.scrollIntoView({ block: "nearest" })
  }

  move(step) {
    const items = this.visible
    if (items.length === 0) return

    this.mark((this.index + step + items.length) % items.length)
  }

  key(event) {
    const meta = event.metaKey || event.ctrlKey

    if (meta && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.toggle()
      return
    }

    if (!this.open) return

    switch (event.key) {
      case "Escape":
        event.preventDefault()
        this.close()
        break
      case "ArrowDown":
        event.preventDefault()
        this.move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.move(-1)
        break
      case "Enter": {
        const current = this.visible[this.index]
        if (!current) return
        event.preventDefault()
        current.click()
        break
      }
    }
  }
}
