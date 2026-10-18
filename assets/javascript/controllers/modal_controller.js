import { Controller } from "../runtime/controllers.js"
import { modified, wrap } from "../runtime/keys.js"

const FOCUSABLE = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  '[tabindex]:not([tabindex="-1"])'
].join(", ")

const SKIP = ["SCRIPT", "TEMPLATE", "LINK", "STYLE"]

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.onKey = (event) => this.key(event)
    this.muted = []
    this.dialog = null

    this.onShortcut = (event) => this.shortcut(event)
    this.onFilterClick = (event) => this.filter(event)
    document.addEventListener("keydown", this.onShortcut)
    document.addEventListener("click", this.onFilterClick)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onShortcut)
    document.removeEventListener("click", this.onFilterClick)
    this.release()
  }

  shortcut(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    if (this.typing(event.target)) return
    if (this.dialog || document.querySelector(".modal.show, .cmdk.open")) return
    if (!this.dialogFor("filter")) return

    event.preventDefault()
    this.reveal("filter", document.activeElement)
  }

  filter(event) {
    if (event.defaultPrevented || event.button !== 0) return
    if (modified(event)) return

    const opener = event.target.closest?.("[data-tm-filter]")
    if (!opener || !this.dialogFor("filter")) return

    event.preventDefault()
    this.reveal("filter", opener)
  }

  reveal(key, opener = null) {
    const dialog = this.dialogFor(key)
    if (!dialog) return

    this.release()
    this.opener = opener
    this.dialog = dialog

    dialog.dispatchEvent(new CustomEvent("dash--modal:open", { detail: { opener } }))
    dialog.hidden = false
    dialog.classList.add("show")

    this.mute(dialog)
    document.addEventListener("keydown", this.onKey)
    this.focusSearch(dialog)
  }

  open(event) {
    this.reveal(event.params.key, event.currentTarget)
  }

  focusSearch(dialog) {
    const panel = dialog.querySelector(".modal-content") || dialog
    const box = dialog.querySelector("input[type='search']")

    if (box) {
      box.focus({ preventScroll: true })
    } else {
      panel.setAttribute("tabindex", "-1")
      panel.focus({ preventScroll: true })
    }

    this.watcher?.disconnect()
    this.watcher = new MutationObserver(() => {
      if (this.dialog !== dialog) return

      const active = document.activeElement
      if (active && active !== document.body && active !== panel && dialog.contains(active)) return

      dialog.querySelector("input[type='search']")?.focus({ preventScroll: true })
    })
    this.watcher.observe(dialog, { childList: true, subtree: true })
  }

  close(event) {
    event?.preventDefault()
    if (!this.dialog) return

    const target = this.returnTarget(this.opener)
    this.release()

    target?.focus()
    this.opener = null
  }

  returnTarget(opener) {
    if (!opener || opener === document.body || !opener.isConnected) return null
    if (opener.offsetParent !== null) return opener

    return opener.closest("[data-controller~='dash--menu']")?.querySelector("[data-dash--menu-target='button']") || null
  }

  backdrop(event) {
    if (event.target === event.currentTarget) this.close(event)
  }

  key(event) {
    if (event.key === "Escape") {
      this.close(event)
      return
    }

    if (event.key === "/") {
      this.find(event)
      return
    }

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.move(event.key === "ArrowDown" ? 1 : -1)
      return
    }

    if (event.key === "Enter") {
      const row = this.rows.find((each) => each.classList.contains("act"))
      if (!row) {
        if (event.target.tagName === "INPUT" && this.dialog.contains(event.target)) event.preventDefault()
        return
      }

      event.preventDefault()
      row.click()
      return
    }

    if (event.key === "Tab") this.trap(event)
  }

  get rows() {
    if (!this.dialog) return []

    return Array.from(this.dialog.querySelectorAll(".data-row")).filter((row) => row.getClientRects().length > 0)
  }

  move(step) {
    const rows = this.rows
    if (rows.length === 0) return

    const at = rows.findIndex((row) => row.classList.contains("act"))
    const next = wrap(at, step, rows.length)

    rows.forEach((row, index) => row.classList.toggle("act", index === next))
    rows[next]?.scrollIntoView({ block: "nearest" })
  }

  find(event) {
    if (this.typing(event.target)) return

    const box = this.dialog?.querySelector("input[type='search']")
    if (!box) return

    event.preventDefault()
    box.focus()
    box.select()
  }

  typing(node) {
    if (!node) return false
    if (node.isContentEditable) return true

    return [ "INPUT", "TEXTAREA", "SELECT" ].includes(node.tagName)
  }

  trap(event) {
    if (!this.dialog) return

    const items = this.focusable

    if (!items.length) {
      event.preventDefault()
      this.dialog.focus()
      return
    }

    const first = items[0]
    const last = items[items.length - 1]
    const active = document.activeElement
    const outside = !this.dialog.contains(active)

    if (event.shiftKey && (active === first || outside)) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && (active === last || outside)) {
      event.preventDefault()
      first.focus()
    }
  }

  release() {
    document.removeEventListener("keydown", this.onKey)
    this.watcher?.disconnect()
    this.watcher = null
    this.unmute()

    if (!this.dialog) return

    this.dialog.querySelectorAll(".data-row.act").forEach((row) => row.classList.remove("act"))
    this.dialog.classList.remove("show")
    this.dialog.hidden = true
    this.dialog = null
  }

  mute(dialog) {
    this.muted = []

    let node = dialog

    while (node && node !== document.body && node.parentElement) {
      Array.from(node.parentElement.children).forEach((sibling) => {
        if (sibling === node || SKIP.includes(sibling.tagName)) return

        this.muted.push([sibling, sibling.getAttribute("aria-hidden"), sibling.inert])
        sibling.setAttribute("aria-hidden", "true")
        sibling.inert = true
      })

      node = node.parentElement
    }
  }

  unmute() {
    this.muted.forEach(([element, hidden, inert]) => {
      if (hidden === null) {
        element.removeAttribute("aria-hidden")
      } else {
        element.setAttribute("aria-hidden", hidden)
      }

      element.inert = inert
    })

    this.muted = []
  }

  dialogFor(key) {
    if (!key) return null

    return this.dialogTargets.find((dialog) => dialog.getAttribute("data-dash--modal-key") === String(key))
  }

  get focusable() {
    if (!this.dialog) return []

    return Array.from(this.dialog.querySelectorAll(FOCUSABLE)).filter(
      (element) => element.getClientRects().length > 0
    )
  }
}
