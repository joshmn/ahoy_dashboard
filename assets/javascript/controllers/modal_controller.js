import { Controller } from "../runtime/controllers.js"

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

    // Bound on the document because a keystroke never passes through a dialog
    // that is still hidden.
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

  // Everything that opens the filter dialog is a link to the dialog as a page:
  // the Filter button, the plus on a chip group, the buttons on a form's rows.
  // Bound on the document so none of them has to name the dialog, and a
  // modified click still opens the page in a tab of its own.
  filter(event) {
    if (event.defaultPrevented || event.button !== 0) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const opener = event.target.closest?.("[data-tm-filter]")
    if (!opener || !this.dialogFor("filter")) return

    event.preventDefault()
    this.reveal("filter", opener)
  }

  // Opening without an opener to return focus to, which is the shortcut's case.
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

  // No preventDefault: the opener carries data-tm-frame and the frame runtime is
  // what loads the details into this dialog's frame.
  open(event) {
    const dialog = this.dialogFor(event.params.key)
    if (!dialog) return

    this.release()

    this.opener = event.currentTarget
    this.dialog = dialog

    dialog.hidden = false
    dialog.classList.add("show")

    this.mute(dialog)
    document.addEventListener("keydown", this.onKey)
    this.focusSearch(dialog)
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

  // Arrow keys walk the rows without moving focus off the search box, so a term
  // can still be edited after picking a way down the list. The position is read
  // off the marked row rather than held as a number, because the filter dialog
  // swaps its rows out on every keystroke and a held index would point into a
  // list that is not there any more.
  get rows() {
    if (!this.dialog) return []

    return Array.from(this.dialog.querySelectorAll(".data-row")).filter((row) => row.getClientRects().length > 0)
  }

  move(step) {
    const rows = this.rows
    if (rows.length === 0) return

    const at = rows.findIndex((row) => row.classList.contains("act"))
    const next = at < 0 ? (step < 0 ? rows.length - 1 : 0) : (at + step + rows.length) % rows.length

    rows.forEach((row, index) => row.classList.toggle("act", index === next))
    rows[next]?.scrollIntoView({ block: "nearest" })
  }

  // Slash focuses the find box, the way it does in the app this is modelled on.
  // Ignored while something is already being typed into, or the shortcut would eat
  // the slash out of a path somebody is searching for.
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

  // Five dialogs share one controller, so the rest of the page is muted
  // relative to whichever one is open: every sibling on the way up from the
  // dialog to the body, which covers the card grid, the other four dialogs and
  // the top bar without naming any of them.
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
