import { CommandDialog, DEBOUNCE_MS } from "../runtime/command_dialog.js"
import { getFragment } from "../runtime/fetch.js"
import { modified } from "../runtime/keys.js"
import { plural } from "../runtime/text.js"

const MINIMUM_TERM = 2

export default class extends CommandDialog {
  static targets = ["panel", "input", "item", "group", "none", "found", "status", "commands", "loading", "failure"]

  disconnect() {
    super.disconnect()
    this.cancel()
    this.commandsRequest?.abort()
  }

  toggle(event) {
    if (event && (event.button > 0 || modified(event))) return

    event?.preventDefault()
    this.isOpen ? this.close() : this.show()
  }

  show() {
    if (!this.hasPanelTarget) return

    this.returnTo = document.activeElement
    this.reveal()
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
      const html = await getFragment(this.panelTarget.dataset.commandsUrl, { frame: "tm-palette-commands", signal: request.signal })
      const focused = document.activeElement
      this.commandsTarget.innerHTML = html
      this.commandsLoaded = true
      if (this.isOpen) {
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
    if (!this.isOpen) return

    this.cancel()
    this.conceal()

    const target = this.returnTo
    this.returnTo = null
    if (target && target !== document.body && target.isConnected) target.focus()
  }

  filter() {
    const term = this.inputTarget.value.trim().toLowerCase()

    this.itemTargets.forEach((item) => {
      item.hidden = term.length > 0 && !item.dataset.term.includes(term)
    })

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

    let html = ""

    try {
      const response = await fetch(url, {
        signal: request.signal,
        credentials: "same-origin",
        headers: { Accept: "text/html" },
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
        : `${commands} ${plural(commands, "command")}, ${values} ${plural(values, "value")} to filter by`
    }

    this.mark(items.length > 0 ? position : -1)
  }

  marked(current) {
    if (!current) {
      this.inputTarget.removeAttribute("aria-activedescendant")
      return
    }

    if (!current.id) current.id = `tm-palette-option-${(this.minted = (this.minted || 0) + 1)}`

    this.inputTarget.setAttribute("aria-activedescendant", current.id)
  }

  key(event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.toggle()
      return
    }

    super.key(event)
  }
}
