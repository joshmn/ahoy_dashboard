import { Controller } from "../runtime/controllers.js"

// The segment and exclusion forms' filters field.
//
// One line per filter. A row's values live in one text box, one per line, which
// is what the form posts, so a pasted list and a list picked in the filter
// dialog end up in the same place. The row shows the first few of them and a count
// until it is opened. Rows and sets added after the page loaded are clones of
// server-rendered templates, so a new one and one that came with the page
// cannot drift.
//
// With the JavaScript off, rows still open, take a pasted list, and come off.
// Only picking in the filter dialog needs this.
//
// The dialog knows nothing about rows or sets. The buttons that open it say
// where its picks should land, and Apply hands them back as one event.

const PLACEHOLDERS = { key: /__key\d*__/g, dimension: "__dimension__", label: "__label__", lower: "__lower__" }
const SHOWN = 3

export default class extends Controller {
  static targets = ["rows", "row", "block", "blockRows", "blockField", "rowTemplate", "blockTemplate", "preview"]
  static values = { prefix: String, previewUrl: String, blocks: Boolean }

  connect() {
    this.aim = null
    this.aimBlock = null
    this.form = this.element.form || this.element.closest("form")
    this.onToggle = (event) => this.toggled(event)

    this.element.addEventListener("toggle", this.onToggle, true)
    this.reveal(this.element)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.onToggle, true)
  }

  toggled(event) {
    const edit = event.target
    if (!edit.matches?.("[data-fx-edit]") || !edit.open) return

    const row = this.rowOf(edit)
    edit.dataset.original = this.textOf(row).value
    this.aim = row
    this.aimBlock = this.blockOf(row)
    this.textOf(row).focus()
  }

  typed(event) {
    this.refresh(this.rowOf(event.currentTarget), { live: true })
  }

  done(event) {
    event.preventDefault()

    const row = this.rowOf(event.currentTarget)
    const values = this.valuesOf(row)

    if (!values.length) {
      this.drop(row)
    } else {
      this.write(row, values)
      this.editOf(row).open = false
    }

    this.changed()
  }

  cancel(event) {
    event.preventDefault()

    const row = this.rowOf(event.currentTarget)
    const edit = this.editOf(row)
    this.textOf(row).value = edit.dataset.original || ""
    edit.open = false

    if (!this.valuesOf(row).length) this.drop(row)
    this.refresh(row)
    this.changed()
  }

  // Picking from traffic for one row opens the dialog on that row's dimension
  // and nothing else, holding the values the row already has, so taking one
  // off in the dialog takes it off the row.
  more(event) {
    const row = this.rowOf(event.currentTarget)
    if (!row) return

    this.aim = row
    this.aimBlock = this.blockOf(row)

    const label = row.querySelector(".fx-dim__name")?.textContent?.trim() || row.dataset.dimension
    const operator = this.operatorOf(row) || "is"
    const values = this.valuesOf(row)
    const tokens = values.length
      ? [{ filters: values.map((value) => ({ dimension: row.dataset.dimension, label, operator, value })) }]
      : []

    event.currentTarget.dataset.tmFilterTokens = JSON.stringify(tokens)
    event.currentTarget.dataset.tmFilterOperator = operator
  }

  andIn(event) {
    this.aim = null
    this.aimBlock = this.blockOf(event.currentTarget)
  }

  newSet() {
    this.aim = null
    this.aimBlock = null
  }

  collect(event) {
    const { groups = [], dimension = null } = event.detail || {}
    const filters = groups.flatMap((group) => group.filters || [])
    const aimed = dimension && this.aim?.isConnected && this.aim.dataset.dimension === dimension ? this.aim : null

    if (aimed) {
      const mine = filters.filter((filter) => filter.dimension === dimension)
      if (mine.length) this.setOperator(aimed, mine[0].operator)

      const values = [...new Set(mine.map((filter) => filter.value))]
      if (!values.length && !this.editOf(aimed).open) {
        this.drop(aimed)
      } else {
        this.write(aimed, values)
      }
    } else {
      filters.forEach((filter) => {
        const row = this.rowFor(filter.dimension, filter.label, filter.operator)
        if (!row) return

        const values = this.valuesOf(row)
        if (!values.includes(filter.value)) this.write(row, [...values, filter.value])

        this.aim = row
        this.aimBlock = this.blockOf(row)
      })
    }

    this.changed()
  }

  removeRow(event) {
    event.preventDefault()

    const row = this.rowOf(event.currentTarget)
    if (row) this.drop(row)

    this.changed()
  }

  removeSet(event) {
    event.preventDefault()

    const block = this.blockOf(event.currentTarget)
    if (!block) return

    if (this.aimBlock === block) this.aimBlock = null
    if (this.aim && block.contains(this.aim)) this.aim = null
    block.remove()
    if (!this.blockTargets.length) this.buildBlock()

    this.changed()
  }

  preview(event) {
    event?.preventDefault()
    if (!this.hasPreviewTarget || !this.previewUrlValue || !this.form) return

    const params = new URLSearchParams()
    const scope = `${this.prefixValue}[rows]`
    for (const [key, value] of new FormData(this.form)) {
      if (key.startsWith(scope)) params.append(key, value)
    }

    const url = new URL(this.previewUrlValue, window.location.href)
    url.search = params.toString()
    this.previewTarget.load?.(url.href)
  }

  changed() {
    this.renumber()
    this.preview()
  }

  renumber() {
    this.blockTargets.forEach((block, number) => {
      block.querySelectorAll("[data-dash--filters-target~='blockField']").forEach((field) => { field.value = String(number) })
      if (!this.blocksValue) return

      const name = `Set ${number + 1}`
      block.querySelector("[data-fx-set]")?.setAttribute("aria-label", name)
      const heading = block.querySelector("[data-fx-set-name]")
      if (heading) heading.textContent = name

      const removal = block.querySelector("[data-fx-set-remove]")
      if (removal) {
        removal.value = `set:${number}`
        removal.setAttribute("aria-label", `Remove ${name.toLowerCase()}`)
      }

      block.querySelector("[data-fx-add]")?.setAttribute("aria-label", `Add a filter to ${name.toLowerCase()}`)
    })
  }

  rowFor(dimension, label, operator = "is") {
    const block = this.aimBlock?.isConnected ? this.aimBlock : (this.blocksValue ? null : this.blockTargets[0])
    const joined = block && this.rowsIn(block).find((row) =>
      !row.hasAttribute("data-mixed") && row.dataset.dimension === dimension && this.operatorOf(row) === operator
    )
    if (joined) return joined

    const target = block || this.emptyBlock() || this.buildBlock()
    const row = target && this.buildRow(dimension, label, target)
    if (row) this.setOperator(row, operator)

    return row
  }

  setOperator(row, operator) {
    const select = row.querySelector("select[name$='[operator]']")
    if (select && Array.from(select.options).some((option) => option.value === operator)) select.value = operator
  }

  emptyBlock() {
    return this.blockTargets.find((block) => !this.rowsIn(block).length)
  }

  drop(row) {
    if (this.aim === row) this.aim = null
    row.remove()
  }

  buildBlock() {
    if (!this.hasRowsTarget || !this.hasBlockTemplateTarget) return null

    const block = this.fragment(this.blockTemplateTarget.innerHTML)
    this.rowsTarget.appendChild(block)
    this.reveal(block)

    return block
  }

  buildRow(dimension, label, block) {
    const holder = block.querySelector("[data-dash--filters-target~='blockRows']")
    if (!holder) return null

    const template = this.rowTemplateTargets.find((each) => each.dataset.dimension === dimension) ||
      this.rowTemplateTargets.find((each) => each.dataset.dimension === "")
    if (!template) return null

    const name = label || dimension
    const html = template.innerHTML
      .replaceAll(PLACEHOLDERS.key, this.newKey())
      .replaceAll(PLACEHOLDERS.dimension, this.escape(dimension))
      .replaceAll(PLACEHOLDERS.label, this.escape(name))
      .replaceAll(PLACEHOLDERS.lower, this.escape(name.toLowerCase()))

    const row = this.fragment(html)
    holder.appendChild(row)
    this.reveal(row)

    return row
  }

  write(row, values) {
    this.textOf(row).value = values.join("\n")
    this.refresh(row)
  }

  refresh(row, { live = false } = {}) {
    const values = this.valuesOf(row)

    row.querySelectorAll("[data-fx-count]").forEach((node) => { node.textContent = String(values.length) })
    row.querySelectorAll("[data-fx-noun]").forEach((node) => { node.textContent = values.length === 1 ? "value" : "values" })
    if (live) return

    const list = row.querySelector("[data-fx-list]")
    const more = row.querySelector("[data-fx-more]")
    const summary = row.querySelector(".fx-values")
    const hidden = Math.max(values.length - SHOWN, 0)

    if (list) list.textContent = values.slice(0, SHOWN).join(", ")
    if (more) {
      more.textContent = `${hidden} more`
      more.hidden = hidden === 0
    }
    if (summary) summary.title = values.join(", ")
  }

  reveal(root) {
    root.querySelectorAll("[data-fx-cancel]").forEach((button) => { button.hidden = false })
  }

  fragment(html) {
    const holder = document.createElement("div")
    holder.innerHTML = html.trim()

    return holder.firstElementChild
  }

  newKey() {
    let key
    do {
      key = `${Date.now()}${Math.floor(Math.random() * 1000)}`
    } while (this.rowTargets.some((row) => row.dataset.key === key))

    return key
  }

  rowOf(element) {
    return element.closest("[data-dash--filters-target~='row']")
  }

  blockOf(element) {
    return element.closest("[data-dash--filters-target~='block']")
  }

  rowsIn(block) {
    return Array.from(block.querySelectorAll("[data-dash--filters-target~='row']"))
  }

  editOf(row) {
    return row.querySelector("[data-fx-edit]")
  }

  textOf(row) {
    return row.querySelector("[data-fx-text]")
  }

  valuesOf(row) {
    const text = this.textOf(row)
    if (!text) return []

    return [...new Set(text.value.split(/\r?\n/).map((line) => line.trim()).filter(Boolean))]
  }

  operatorOf(row) {
    return row.querySelector("select[name$='[operator]']")?.value
  }

  escape(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
  }
}
