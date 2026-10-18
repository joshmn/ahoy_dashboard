import { Controller } from "../runtime/controllers.js"
import { getFragment } from "../runtime/fetch.js"
import { plural } from "../runtime/text.js"

const DEBOUNCE_MS = 200
const MINIMUM_TERM = 2
const JOINING = ["is", "contains"]
const DEFAULT_OPERATOR = "is"
const PREFIX = /^\s*([^:]{1,40}):\s*(.*)$/
const ROW = ".fm-row[data-value]"
const FULL_KEY = "ahoy_dashboard.filter_modal.full"

const normalize = (text) => String(text || "").toLowerCase().replace(/[^a-z0-9]/g, "")

const SPLIT_OVER = 24
const SPLIT_TAIL = 16
const SPLIT_TAIL_MAX = 24

const tailOf = (text) => {
  const cut = text.lastIndexOf("/", text.length - 2)

  return cut <= 0 || text.length - cut > SPLIT_TAIL_MAX ? text.slice(-SPLIT_TAIL) : text.slice(cut)
}

const element = (tag, className, text) => {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text !== undefined) node.textContent = text

  return node
}

export default class extends Controller {
  static targets = ["input", "inputLabel", "tokens", "scope", "scopeName", "scopeValues", "operator", "another", "rail", "body", "status", "apply", "clear", "expander", "loading", "loadingStatus", "retry"]
  static values = { url: String, apply: String, tokens: Array, operators: Object, collect: Boolean, none: String, contents: String }

  connect() {
    this.groups = this.copy(this.tokensValue)
    this.scope = null
    this.locked = false
    this.operator = DEFAULT_OPERATOR
    this.opener = null
    this.loaded = null

    this.onOpen = (event) => {
      const opener = event.detail.opener
      this.opener = opener && this.ownsOpener(opener) ? opener : null
    }
    this.element.addEventListener("dash--modal:open", this.onOpen)

    this.watcher = new MutationObserver(() => this.visibility())
    this.watcher.observe(this.element, { attributes: true, attributeFilter: ["hidden"] })
    this.shown = !this.element.hidden

    this.full(this.remembered())
    if (this.hasInputTarget) this.render()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.element.removeEventListener("dash--modal:open", this.onOpen)
    this.watcher?.disconnect()
    this.contentsRequest?.abort()
  }

  ownsOpener(opener) {
    const field = opener.closest("[data-controller~='dash--filters']")

    return this.collectValue ? field !== null && field.contains(this.element) : field === null
  }

  async visibility() {
    const shown = !this.element.hidden
    if (shown === this.shown) return

    this.shown = shown
    this.opening = (this.opening || 0) + 1
    const opening = this.opening
    const opener = this.opener
    this.activeOpener = opener
    this.opener = null
    if (!shown) return

    const ready = await this.loadContents()
    if (ready && this.shown && this.opening === opening) this.opened(opener)
  }

  async loadContents() {
    if (this.hasInputTarget) return true
    if (this.loadingContents) return this.loadingContents

    this.loadingContents = this.fetchContents()
    const ready = await this.loadingContents
    this.loadingContents = null
    return ready
  }

  async fetchContents() {
    const request = new AbortController()
    this.contentsRequest = request
    this.loadingTarget.setAttribute("aria-busy", "true")
    this.loadingStatusTarget.textContent = "Loading filters…"
    this.retryTarget.hidden = true

    try {
      const html = await getFragment(this.contentsValue, { frame: "tm-filter-controls", signal: request.signal })
      const document = new DOMParser().parseFromString(html, "text/html")
      const content = document.querySelector("#tm-filter-modal .modal-content")
      if (!content?.querySelector("[data-dash--filter-modal-target='input']")) throw new Error("Filter controls are missing")

      this.loadingTarget.replaceWith(...Array.from(content.children).filter((child) => !child.classList.contains("modal-header")))
      return true
    } catch (error) {
      if (error.name !== "AbortError") {
        this.loadingStatusTarget.textContent = "Filters could not be loaded. Try again or open them as a page."
        this.loadingTarget.setAttribute("aria-busy", "false")
        this.retryTarget.hidden = false
      }
      return false
    } finally {
      this.contentsRequest = null
    }
  }

  async retry(event) {
    event.preventDefault()
    const ready = await this.loadContents()
    if (ready && this.shown) this.opened(this.activeOpener)
  }

  opened(opener) {
    const data = opener?.dataset || {}

    this.groups = this.copy(data.tmFilterTokens ? JSON.parse(data.tmFilterTokens) : this.tokensValue)
    this.locked = "tmFilterLocked" in data
    this.operator = data.tmFilterOperator || DEFAULT_OPERATOR
    this.scope = data.tmFilterDimension ? this.dimension(data.tmFilterDimension) : null
    if (!this.scope) this.locked = false

    this.inputTarget.value = ""
    this.loaded = null
    this.render()
    if (this.scope || this.openedBefore) this.load()
    this.openedBefore = true
  }

  expand(event) {
    event?.preventDefault()

    const on = !this.element.classList.contains("fm--full")
    this.full(on)
    this.remember(on)
  }

  full(on) {
    this.element.classList.toggle("fm--full", on)
    this.element.querySelector(".modal-dialog")?.classList.toggle("modal-fullscreen", on)
    if (!this.hasExpanderTarget) return

    this.expanderTarget.setAttribute("aria-pressed", String(on))
    this.expanderTarget.title = on ? "Exit full screen" : "Full screen"
  }

  remembered() {
    try {
      return window.localStorage.getItem(FULL_KEY) === "1"
    } catch {
      return false
    }
  }

  remember(on) {
    try {
      if (on) {
        window.localStorage.setItem(FULL_KEY, "1")
      } else {
        window.localStorage.removeItem(FULL_KEY)
      }
    } catch {
      return
    }
  }

  box(event) {
    const target = event.target
    if (target.closest(".fm-x, select")) return

    const token = target.closest("[data-fm-token]")
    if (token) {
      if (!target.closest("button")) this.open(Number(token.dataset.index))
      return
    }

    if (this.scopeTarget.contains(target)) {
      if (!target.closest("button")) this.inputTarget.focus()
      return
    }

    if (this.scope && !this.locked) {
      this.unscope()
    } else {
      this.inputTarget.focus()
    }
  }

  search() {
    const prefix = !this.scope && PREFIX.exec(this.inputTarget.value)
    const named = prefix && this.dimension(prefix[1])

    if (named) {
      this.inputTarget.value = prefix[2]
      this.setScope(named)
    }

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), DEBOUNCE_MS)
    this.mode()
  }

  scopeTo(event) {
    event.preventDefault()

    const { dimension, label } = event.currentTarget.dataset
    if (!dimension || this.locked) return

    this.setScope({ dimension, label })
    this.load()
    this.inputTarget.focus()
  }

  unscope(event) {
    event?.preventDefault()
    if (this.locked || !this.scope) return

    this.scope = null
    this.operator = DEFAULT_OPERATOR
    this.inputTarget.value = ""
    this.render()
    this.load()
    this.inputTarget.focus()
  }

  setScope(scope) {
    this.scope = scope
    const joined = this.groups.find((group) => this.uniformOn(group, scope.dimension))
    this.operator = joined ? joined.filters[0].operator : DEFAULT_OPERATOR
    this.render()
  }

  operate() {
    this.operator = this.operatorTarget.value
    this.render()
  }

  key(event) {
    const input = this.inputTarget
    const empty = input.value === ""

    if (event.key === "Backspace" && empty) {
      const building = this.building()

      if (building.length) {
        this.hold(event)
        this.dropFrom(building[building.length - 1])
      } else if (this.scope && !this.locked) {
        this.hold(event)
        this.unscope()
      } else if (!this.scope && this.groups.length) {
        this.hold(event)
        this.dropFrom(this.groups[this.groups.length - 1])
      }
      return
    }

    if (event.key === "Escape") {
      if (!empty) {
        this.hold(event)
        input.value = ""
        this.load()
      } else if (this.scope && !this.locked) {
        this.hold(event)
        this.unscope()
      }
      return
    }

    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      this.hold(event)
      this.apply()
      return
    }

    if (event.key === "Enter" && this.scope && !this.element.querySelector(`${ROW}.act`)) {
      const target = this.defaultRow()
      if (!target) return

      this.hold(event)
      target.click()
    }
  }

  defaultRow() {
    const rows = Array.from(this.element.querySelectorAll(ROW))
    const typed = rows.find((row) => "typed" in row.dataset)
    const found = rows.find((row) => !("typed" in row.dataset))

    return this.operator.includes("contains") ? typed || found : found || typed
  }

  hold(event) {
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  pick(event) {
    event.preventDefault()

    const { dimension, label, value } = event.currentTarget.dataset
    if (!dimension || value === undefined) return

    this.toggle({ dimension, label, operator: this.scope ? this.operator : DEFAULT_OPERATOR, value })
    this.render()
    this.inputTarget.focus({ preventScroll: true })
  }

  toggle(filter) {
    const at = this.locate(filter)

    if (at) {
      const [group, index] = at
      group.filters.splice(index, 1)
      this.prune(group)
      return
    }

    const joined = JOINING.includes(filter.operator) &&
      this.groups.find((group) => this.uniformOn(group, filter.dimension) && group.filters[0].operator === filter.operator)

    if (joined) {
      joined.filters.push(filter)
    } else {
      this.groups.push({ filters: [filter] })
    }
  }

  locate({ dimension, operator, value }) {
    for (const group of this.groups) {
      const index = group.filters.findIndex((each) =>
        each.dimension === dimension && each.operator === operator && each.value === value
      )
      if (index !== -1) return [group, index]
    }

    return null
  }

  uniformOn(group, dimension) {
    return group.filters.length > 0 && group.filters.every((each) =>
      each.dimension === dimension && each.operator === group.filters[0].operator
    )
  }

  jump(event) {
    event.preventDefault()

    this.open(Number(event.currentTarget.dataset.index))
  }

  open(index) {
    const group = this.groups[index]
    if (!group || this.locked) return

    const first = group.filters[0]
    if (!this.uniformOn(group, first.dimension)) return

    this.scope = this.dimension(first.dimension) || { dimension: first.dimension, label: first.label }
    this.operator = first.operator
    this.inputTarget.value = ""
    this.render()
    this.load()
    this.inputTarget.focus()
  }

  removeValue(event) {
    event.preventDefault()

    const group = this.groups[Number(event.currentTarget.dataset.group)]
    const position = Number(event.currentTarget.dataset.position)
    if (!group || Number.isNaN(position)) return

    group.filters.splice(position, 1)
    this.prune(group)

    this.render()
    this.inputTarget.focus()
  }

  dropFrom(group) {
    group.filters.pop()
    this.prune(group)

    this.render()
  }

  prune(group) {
    if (!group.filters.length) this.groups.splice(this.groups.indexOf(group), 1)
  }

  building() {
    if (!this.scope) return []

    return this.groups.filter((group) =>
      this.uniformOn(group, this.scope.dimension) && group.filters[0].operator === this.operator
    )
  }

  clear(event) {
    event?.preventDefault()

    this.groups = []
    if (!this.locked) {
      this.scope = null
      this.operator = DEFAULT_OPERATOR
      this.inputTarget.value = ""
      this.load()
    }

    this.render()
    this.inputTarget.focus()
  }

  apply(event) {
    event?.preventDefault()

    if (this.collectValue) {
      this.element.dispatchEvent(new CustomEvent("dash--filter-modal:apply", {
        bubbles: true,
        detail: { groups: this.copy(this.groups), dimension: this.locked ? this.scope?.dimension : null }
      }))
      this.element.querySelector("[data-action~='dash--modal#close']")?.click()
      return
    }

    const url = new URL(this.applyValue, window.location.origin)
    this.append(url.searchParams)
    window.location.assign(url.pathname + url.search)
  }

  append(params) {
    params.delete("filters")
    if (!this.groups.length) {
      params.set("filters", this.noneValue)
      return
    }

    this.groups.forEach((group, position) => {
      group.filters.forEach((filter) => {
        params.append("filters[][dimension]", filter.dimension)
        params.append("filters[][operator]", filter.operator)
        params.append("filters[][value]", filter.value)
        if (group.filters.length > 1) params.append("filters[][group]", String(position))
      })
    })
  }

  async load() {
    clearTimeout(this.timer)

    const url = new URL(this.urlValue, window.location.origin)
    const term = this.inputTarget.value.trim()

    if (term) url.searchParams.set("q", term)
    if (this.scope) url.searchParams.set("dimension", this.scope.dimension)
    if (!this.collectValue) this.append(url.searchParams)

    const src = url.pathname + url.search
    this.mode()
    if (src === this.loaded) return

    this.loaded = src
    await this.frame?.load(src)
    this.mark()
  }

  mode() {
    const term = this.inputTarget.value.trim()
    this.bodyTarget.dataset.mode = this.scope ? "scoped" : (term.length >= MINIMUM_TERM ? "search" : "browse")
  }

  render() {
    this.renderTokens()
    this.renderScope()
    this.mark()
    this.mode()
    this.renderStatus()
  }

  renderTokens() {
    const building = this.building()
    const items = []
    let placed = false

    this.groups.forEach((group, index) => {
      if (!building.includes(group)) {
        items.push(this.token(group, index))
      } else if (!placed) {
        items.push(this.scopeTarget)
        placed = true
      }
    })
    if (!placed) items.push(this.scopeTarget)

    this.tokensTarget.replaceChildren(...items)
    this.tokensTarget.hidden = items.length === 1 && this.scope === null
  }

  token(group, index) {
    const item = element("li", "badge bg-primary-subtle text-primary-emphasis border border-primary-subtle d-inline-flex flex-wrap align-items-center gap-1 mw-100 fm-token")
    const first = group.filters[0]
    const uniform = this.uniformOn(group, first.dimension)

    if (uniform && !this.locked) {
      item.dataset.fmToken = ""
      item.dataset.index = String(index)
      item.title = `Change ${this.say(group)}`
    }

    if (uniform) {
      const head = element("button", "fm-token__head", `${first.label} ${this.words(first.operator)}`)
      head.type = "button"
      head.dataset.index = String(index)
      head.setAttribute("data-action", "dash--filter-modal#jump")
      head.setAttribute("aria-label", `Change ${this.say(group)}`)
      head.disabled = this.locked
      item.append(head)
    }

    this.values(item, [[group, index]], uniform)
    return item
  }

  values(holder, groups, bare) {
    let first = true

    groups.forEach(([group, index]) => {
      group.filters.forEach((filter, position) => {
        if (!first) holder.append(element("span", "fm-token__or", JOINING.includes(filter.operator) ? "or" : "and"))
        first = false

        holder.append(this.value(filter, index, position, bare))
      })
    })
  }

  value(filter, index, position, bare) {
    const whole = `${filter.label} ${this.words(filter.operator)} ${filter.value}`
    const chip = element("span", "d-inline-flex align-items-center gap-1 mw-100 min-w-0 fm-value")

    if (!bare) chip.append(element("span", "flex-shrink-0", `${filter.label} ${this.words(filter.operator)}`))
    chip.append(this.shortened(filter.value))

    const remove = element("button", "btn-close fm-x")
    remove.type = "button"
    remove.dataset.group = String(index)
    remove.dataset.position = String(position)
    remove.setAttribute("data-action", "dash--filter-modal#removeValue")
    remove.setAttribute("aria-label", `Remove ${whole}`)
    chip.append(remove)

    return chip
  }

  shortened(text) {
    if (text.length <= SPLIT_OVER) {
      const plain = element("span", "nm", text)
      plain.title = text
      return plain
    }

    const tail = tailOf(text)
    const split = element("span", "nm nm--split")
    split.title = text
    split.append(element("span", "nm__head", text.slice(0, -tail.length)), element("span", "nm__tail", tail))

    return split
  }

  renderScope() {
    const scoped = this.scope !== null

    this.scopeTarget.hidden = !scoped
    this.anotherTarget.hidden = !scoped || this.locked
    this.operatorTarget.value = this.operator

    if (scoped) this.scopeNameTarget.textContent = this.scope.label

    const building = this.building()
    this.scopeValuesTarget.replaceChildren()
    this.values(this.scopeValuesTarget, building.map((group) => [group, this.groups.indexOf(group)]), true)
    this.scopeValuesTarget.hidden = building.length === 0

    const noun = scoped ? this.scope.label.toLowerCase() : null
    const hint =
      !scoped ? "Search or pick a dimension"
        : this.operator.includes("contains") ? `Type part of the ${noun}, then Enter`
          : `Type to narrow ${noun} values`

    this.inputTarget.placeholder = hint
    this.inputLabelTarget.textContent = scoped ? `Search ${noun} values` : "Search every value"
  }

  renderStatus() {
    const count = this.groups.reduce((sum, group) => sum + group.filters.length, 0)

    if (this.collectValue) {
      this.statusTarget.textContent = count ? `${count} ${plural(count, "value")} picked` : "Nothing picked yet"
    } else {
      this.statusTarget.textContent = count ? `${count} ${plural(count, "filter")}` : "No filters"
    }

    this.clearTarget.hidden = count === 0
  }

  mark() {
    const operator = this.scope ? this.operator : DEFAULT_OPERATOR

    this.element.querySelectorAll(ROW).forEach((row) => {
      const on = this.locate({ dimension: row.dataset.dimension, operator, value: row.dataset.value }) !== null
      row.setAttribute("aria-pressed", String(on))
    })

    if (!this.hasRailTarget) return

    this.railTarget.querySelectorAll("[data-dimension]").forEach((link) => {
      const count = this.groups.reduce((sum, group) =>
        sum + group.filters.filter((each) => each.dimension === link.dataset.dimension).length, 0)
      const badge = link.querySelector("[data-fm-count]")

      if (badge) {
        badge.textContent = String(count)
        badge.hidden = count === 0
      }

      const current = link.dataset.dimension === this.scope?.dimension
      link.classList.toggle("active", current)
      link.toggleAttribute("aria-current", current)
    })
  }

  words(operator) {
    return this.operatorsValue[operator] || operator
  }

  say(group) {
    const first = group.filters[0]

    if (this.uniformOn(group, first.dimension)) {
      return `${first.label} ${this.words(first.operator)} ${group.filters.map((each) => each.value).join(" or ")}`
    }

    return group.filters.map((each) => `${each.label} ${this.words(each.operator)} ${each.value}`).join(" or ")
  }

  dimension(name) {
    if (!this.hasRailTarget) return null

    const wanted = normalize(name)
    const link = Array.from(this.railTarget.querySelectorAll("[data-dimension]")).find((each) =>
      normalize(each.dataset.dimension) === wanted || normalize(each.dataset.label) === wanted
    )

    return link ? { dimension: link.dataset.dimension, label: link.dataset.label } : null
  }

  copy(groups) {
    return (groups || []).map((group) => ({ filters: (group.filters || []).map((filter) => ({ ...filter })) }))
  }

  get frame() {
    return this.element.querySelector("tm-frame")
  }
}
